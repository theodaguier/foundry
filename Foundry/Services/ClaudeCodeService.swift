import Foundation

enum ClaudeCodeService {

    enum ClaudeEvent: Sendable {
        case toolUse(tool: String, filePath: String?, detail: String?)
        case toolResult(tool: String, output: String)
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
                    for event in parseEvents(line) {
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

        // Append raw output to generation.log (accumulates all Claude phases)
        let logFile = projectDir.appendingPathComponent("generation.log")
        let separator = "\n" + String(repeating: "=", count: 80) + "\n"
        let header = "DATE: \(Date())\nPROMPT: \(String(prompt.prefix(200)))\nEXIT: \(exitCode)\(timedOut ? " (TIMEOUT)" : "")\n" + String(repeating: "-", count: 80) + "\n"
        let section = separator + header + "\n--- STDOUT ---\n\(allOutput)\n\n--- STDERR ---\n\(stderrOutput)\n"
        if let data = section.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path),
               let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logFile)
            }
        }

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
            "--disallowedTools", "Bash",
            "--append-system-prompt",
            """
            You MUST use tools (Read, Edit, Write, MultiEdit) on every turn. Never respond with only text.
            Read CLAUDE.md first — it is your complete reference. Follow its phases in order.
            Use Edit to modify existing method stubs. NEVER add duplicate method definitions.
            Your output is automatically validated — empty stubs will be rejected.
            CRITICAL: Do NOT use Bash. Do NOT run grep, echo, or any shell command to verify your work.
            Trust your edits. If you need to check a file, use Read.
            """,
        ]
    }

    // MARK: - Event parser
    //
    // Claude CLI --output-format stream-json emits COMPLETE messages, not streaming deltas.
    // Each line is one of: system | assistant | tool | result | rate_limit_event
    // There are NO content_block_delta events. Silence between events = API round-trip time.

    private static func parseEvents(_ line: String) -> [ClaudeEvent] {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let type = json["type"] as? String ?? ""
        var events: [ClaudeEvent] = []

        switch type {

        case "system":
            if json["subtype"] as? String == "init" {
                let tools = (json["tools"] as? [String]) ?? []
                let mcpServers = (json["mcp_servers"] as? [[String: Any]]) ?? []
                let connected = mcpServers.filter { $0["status"] as? String == "connected" }
                let needsAuth = mcpServers.filter { $0["status"] as? String == "needs-auth" }
                var parts = ["Claude \(json["claude_code_version"] as? String ?? "") ready"]
                if !connected.isEmpty {
                    let names = connected.compactMap { $0["name"] as? String }.joined(separator: ", ")
                    parts.append("MCP: \(names)")
                }
                if !needsAuth.isEmpty {
                    parts.append("\(needsAuth.count) MCP need auth (skipped)")
                }
                events.append(.text(parts.joined(separator: " · ")))
            }

        case "assistant":
            guard let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { break }
            for block in content {
                switch block["type"] as? String {
                case "text":
                    if let text = block["text"] as? String, !text.isEmpty {
                        events.append(.text(text))
                    }
                case "tool_use":
                    if let name = block["name"] as? String {
                        let input = block["input"] as? [String: Any] ?? [:]
                        let filePath = extractPath(from: input)
                        let detail = buildToolDetail(tool: name, input: input)
                        events.append(.toolUse(tool: name, filePath: filePath, detail: detail))
                    }
                default: break
                }
            }

        case "tool", "tool_result":
            // Tool results: what Claude got back (Read file contents, Write confirmation, etc.)
            let output = extractToolOutput(from: json)
            let toolName = json["tool_name"] as? String ?? json["name"] as? String ?? "tool"
            if !output.isEmpty {
                events.append(.toolResult(tool: toolName, output: output))
            }

        case "result":
            let isError = json["is_error"] as? Bool ?? false
            // Show cost and turn count if available
            if let cost = json["total_cost_usd"] as? Double, let turns = json["num_turns"] as? Int {
                events.append(.text(String(format: "Done — %d turns, $%.4f", turns, cost)))
            }
            events.append(.result(success: !isError))

        default:
            break
        }

        return events
    }

    private static func buildToolDetail(tool: String, input: [String: Any]) -> String? {
        let lower = tool.lowercased()
        if lower.contains("write") {
            if let content = input["content"] as? String {
                return "\(content.components(separatedBy: .newlines).count) lines"
            }
        }
        if lower.contains("edit") || lower.contains("str_replace") {
            if let old = input["old_str"] as? String {
                let first = old.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines).first ?? ""
                return "«\(String(first.prefix(50)))»"
            }
        }
        if lower.contains("multiedit") || lower.contains("multi_edit") {
            if let edits = input["edits"] as? [[String: Any]] { return "\(edits.count) edits" }
        }
        return nil
    }

    private static func extractPath(from input: [String: Any]) -> String? {
        for key in ["file_path", "target_file", "path", "file", "filename"] {
            if let p = input[key] as? String { return p }
        }
        return nil
    }

    private static func extractToolOutput(from json: [String: Any]) -> String {
        if let s = json["content"] as? String { return s }
        if let arr = json["content"] as? [[String: Any]] {
            return arr.compactMap { $0["content"] as? String ?? $0["text"] as? String }.joined(separator: "\n")
        }
        if let s = json["output"] as? String { return s }
        return ""
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

    /// Returns current content and resets the buffer to empty.
    func flush() -> String {
        lock.lock()
        defer { lock.unlock() }
        let content = buffer
        buffer = ""
        return content
    }
}
