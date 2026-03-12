import Foundation

enum ClaudeCodeService {

    enum ClaudeEvent {
        case toolUse(tool: String, filePath: String?)
        case text(String)
        case result(success: Bool)
        case error(String)
    }

    struct RunResult {
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
        // Build command — run through login shell to get user's full PATH
        let escapedPrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")
        let claudeCmd = "claude -p '\(escapedPrompt)' --dangerously-skip-permissions --output-format stream-json --verbose --max-turns 30"

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", claudeCmd]
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
        // Read current file contents so Claude has full context for the fix
        let sourceDir = projectDir.appendingPathComponent("Source")
        let fileContext = readSourceFiles(sourceDir: sourceDir)

        let prompt = """
        The JUCE plugin build failed (attempt \(attempt)/3). Fix ALL errors.

        ## Compiler errors:
        \(errors)

        ## Current source files:
        \(fileContext)

        ## CRITICAL RULES:
        - ONLY edit files in Source/: PluginProcessor.h, PluginProcessor.cpp, PluginEditor.h, PluginEditor.cpp
        - ABSOLUTELY DO NOT touch CMakeLists.txt — it is correct and must not be modified
        - ABSOLUTELY DO NOT touch FoundryLookAndFeel.h — it is correct and must not be modified
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

    /// Read all source files to provide context for error fixing
    private static func readSourceFiles(sourceDir: URL) -> String {
        var result = ""
        let files = ["PluginProcessor.h", "PluginProcessor.cpp", "PluginEditor.h", "PluginEditor.cpp"]
        for file in files {
            let url = sourceDir.appendingPathComponent(file)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                result += "\n### \(file):\n```cpp\n\(content)\n```\n"
            }
        }
        return result
    }

    // MARK: - Line parser

    private static func parseLine(_ line: String) -> ClaudeEvent? {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let toolName = extractToolName(from: json) {
            let filePath = extractFilePath(from: json)
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
                   let path = input["file_path"] as? String {
                    return path
                }
            }
        }
        if let input = json["input"] as? [String: Any] {
            return input["file_path"] as? String
        }
        if let block = json["content_block"] as? [String: Any],
           let input = block["input"] as? [String: Any] {
            return input["file_path"] as? String
        }
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
