import Foundation

enum ClaudeCodeService {

    enum ClaudeEvent: Sendable {
        case toolUse(tool: String, filePath: String?)
        case text(String)
        case result(success: Bool)
        case error(String)
    }

    struct RunResult: Sendable {
        var success: Bool
        var output: String
        var error: String?
    }

    // MARK: - Generate

    static func run(
        prompt: String,
        projectDir: URL,
        timeoutSeconds: Int = 600,
        onEvent: @escaping @Sendable (ClaudeEvent) -> Void
    ) async -> RunResult {
        guard let claudePath = DependencyChecker.resolveCommandPath("claude") else {
            let message = """
            Claude Code CLI is not available in Foundry's runtime environment.
            Open Setup and make sure `claude` is installed, then retry.
            """
            onEvent(.error(message))
            return RunResult(success: false, output: "", error: message)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = Self.buildArguments(prompt: prompt)

        process.currentDirectoryURL = projectDir
        process.environment = DependencyChecker.shellEnvironment
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let outputCollector = StreamCollector()
        let errorCollector = StreamCollector()

        // Drain pipes continuously to avoid buffer deadlock
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                outputCollector.append(text)
                for line in text.components(separatedBy: .newlines) {
                    if let event = parseLine(line) {
                        onEvent(event)
                    }
                }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                errorCollector.append(text)
            }
        }

        do {
            try process.run()
        } catch {
            return RunResult(success: false, output: "", error: "Failed to launch Claude Code: \(error.localizedDescription)")
        }

        // Simple approach: waitUntilExit on a background thread.
        // A DispatchSource timer sends terminate() on timeout.
        // After terminate(), waitUntilExit completes naturally.
        let timeoutTimer = DispatchSource.makeTimerSource(queue: .global())
        timeoutTimer.schedule(deadline: .now() + .seconds(timeoutSeconds))
        timeoutTimer.setEventHandler { [process] in
            if process.isRunning {
                process.terminate()
            }
        }
        timeoutTimer.resume()

        // Block a background thread until process exits
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                c.resume()
            }
        }

        timeoutTimer.cancel()

        // Small delay to let readability handlers drain
        try? await Task.sleep(for: .milliseconds(200))
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // Now safe to read terminationStatus — process has exited
        let exitCode = process.terminationStatus
        let timedOut = exitCode == 15 || exitCode == 143 // SIGTERM

        let allOutput = outputCollector.result
        let stderrOutput = errorCollector.result

        // Diagnostic: save raw output to project dir
        let logFile = projectDir.appendingPathComponent("claude-output.log")
        let logContent = "EXIT CODE: \(exitCode)\n\n--- STDOUT ---\n\(allOutput)\n\n--- STDERR ---\n\(stderrOutput)"
        try? logContent.write(to: logFile, atomically: true, encoding: .utf8)

        if timedOut {
            onEvent(.error("Generation timed out after \(timeoutSeconds / 60) minutes"))
        }
        onEvent(.result(success: exitCode == 0))

        return RunResult(
            success: exitCode == 0,
            output: allOutput,
            error: exitCode == 0 ? nil : timedOut
                ? "Generation timed out after \(timeoutSeconds / 60) minutes"
                : stderrOutput.isEmpty
                    ? "Claude Code exited with code \(exitCode)"
                    : stderrOutput
        )
    }

    /// Runs Claude Code to fix build errors
    static func fix(
        errors: String,
        projectDir: URL,
        attempt: Int,
        onEvent: @escaping @Sendable (ClaudeEvent) -> Void
    ) async -> RunResult {
        let prompt = """
        The JUCE plugin build failed (attempt \(attempt)/3). Fix ALL errors.
        Read the source files in Source/ to understand the current state, then fix.

        ## Compiler errors:
        \(errors)

        ## CRITICAL RULES:
        - ONLY edit files in Source/: PluginProcessor.h, PluginProcessor.cpp, PluginEditor.h, PluginEditor.cpp, FoundryLookAndFeel.h
        - ABSOLUTELY DO NOT touch CMakeLists.txt — it is correct and must not be modified
        - Use only JUCE built-in classes, no external dependencies
        - C++17 standard
        - Fully qualify all JUCE types with juce:: namespace
        - All method signatures in .cpp must match .h declarations exactly
        - Do not use juce::Font(float) — use juce::Font(juce::FontOptions(float)) instead
        - All parameters in createParameterLayout() must have matching UI controls
        - If a linker error mentions undefined symbols, the issue is in your source code, NOT in CMakeLists.txt
        """

        return await run(
            prompt: prompt,
            projectDir: projectDir,
            timeoutSeconds: 180,
            onEvent: onEvent
        )
    }

    // MARK: - Argument builder

    static func buildArguments(prompt: String) -> [String] {
        [
            "-p",
            prompt,
            "--dangerously-skip-permissions",
            "--output-format", "stream-json",
            "--verbose",
            "--max-turns", "50",
            "--model", "sonnet",
            "--append-system-prompt",
            """
            You MUST use tools (Read, Edit, Write, Bash) on every turn. Never respond with only text — always take action by reading or editing files.
            CRITICAL C++ RULES:
            - Use `const auto&` to iterate value types (std::pair, struct). NEVER `auto*` — that is a pointer dereference and will not compile.
            - Never add a new definition for a method that already exists in the .cpp file. Use Edit to MODIFY the existing implementation.
            - All JUCE types must be fully qualified with juce:: prefix.
            - Use juce::Font(juce::FontOptions(float)) — never juce::Font(float).
            """,
        ]
    }

    // MARK: - Line parser

    private static func parseLine(_ line: String) -> ClaudeEvent? {
        guard !line.isEmpty else {
            return nil
        }

        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return inferFileActivity(from: line)
        }

        if let toolName = extractToolName(from: json) {
            let filePath = extractFilePath(from: json) ?? inferFilePath(from: line)
            return .toolUse(tool: toolName, filePath: filePath)
        }

        if let type = json["type"] as? String, type == "result" {
            let isError = json["is_error"] as? Bool ?? false
            return .result(success: !isError)
        }

        return nil
    }

    private static func extractToolName(from json: [String: Any]) -> String? {
        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            for block in content {
                if block["type"] as? String == "tool_use",
                   let name = block["name"] as? String {
                    return name
                }
            }
        }
        if json["type"] as? String == "tool_use" {
            return json["name"] as? String
        }
        if let block = json["content_block"] as? [String: Any],
           block["type"] as? String == "tool_use" {
            return block["name"] as? String
        }
        return nil
    }

    private static func extractFilePath(from json: [String: Any]) -> String? {
        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            for block in content {
                if let input = block["input"] as? [String: Any],
                   let path = extractPath(from: input) {
                    return path
                }
            }
        }
        if let input = json["input"] as? [String: Any] {
            return extractPath(from: input)
        }
        if let block = json["content_block"] as? [String: Any],
           let input = block["input"] as? [String: Any] {
            return extractPath(from: input)
        }
        return nil
    }

    private static func extractPath(from input: [String: Any]) -> String? {
        if let path = input["file_path"] as? String { return path }
        if let path = input["target_file"] as? String { return path }
        if let path = input["path"] as? String { return path }
        if let path = input["file"] as? String { return path }
        if let path = input["filename"] as? String { return path }
        return nil
    }

    private static func inferFileActivity(from line: String) -> ClaudeEvent? {
        guard let path = inferFilePath(from: line) else { return nil }
        return .toolUse(tool: "inferred_file_activity", filePath: path)
    }

    private static func inferFilePath(from line: String) -> String? {
        if line.contains("PluginEditor.cpp") { return "PluginEditor.cpp" }
        if line.contains("PluginEditor.h") { return "PluginEditor.h" }
        if line.contains("PluginProcessor.cpp") { return "PluginProcessor.cpp" }
        if line.contains("PluginProcessor.h") { return "PluginProcessor.h" }
        if line.contains("FoundryLookAndFeel.h") { return "FoundryLookAndFeel.h" }
        return nil
    }
}

// MARK: - Thread-safe string collector

private final class StreamCollector: @unchecked Sendable {
    private var buffer = ""
    private let lock = NSLock()

    func append(_ text: String) {
        lock.lock()
        buffer += text
        lock.unlock()
    }

    var result: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
