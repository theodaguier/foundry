import Foundation

/// Codex (OpenAI) agent service — wraps the `codex` CLI binary.
/// Mirrors ClaudeCodeService's structure: enum with static methods, Process-based execution.
enum CodexService {

    /// 15-minute watchdog — same safety net as ClaudeCodeService.
    private static let watchdogSeconds = 900

    // MARK: - Run

    static func run(
        prompt: String,
        projectDir: URL,
        model: AgentModel,
        onEvent: @escaping @Sendable (AgentEvent) -> Void
    ) async -> AgentRunResult {
        guard let codexPath = DependencyChecker.resolveCommandPath("codex") else {
            let message = """
            Codex CLI is not available in Foundry's runtime environment.
            Open Setup and make sure `codex` is installed, then retry.
            """
            onEvent(.error(message))
            return AgentRunResult(success: false, output: "", error: message)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = buildArguments(prompt: prompt, model: model)
        process.currentDirectoryURL = projectDir
        process.environment = DependencyChecker.shellEnvironment
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let outputCollector = StreamCollector()
        let errorCollector = StreamCollector()

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
            return AgentRunResult(success: false, output: "", error: "Failed to launch Codex: \(error.localizedDescription)")
        }

        // Watchdog
        let watchdog = DispatchSource.makeTimerSource(queue: .global())
        watchdog.schedule(deadline: .now() + .seconds(watchdogSeconds))
        watchdog.setEventHandler { [process] in
            if process.isRunning { process.terminate() }
        }
        watchdog.resume()

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                c.resume()
            }
        }

        watchdog.cancel()

        try? await Task.sleep(for: .milliseconds(200))
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let exitCode = process.terminationStatus
        let timedOut = exitCode == 15 || exitCode == 143

        let allOutput = outputCollector.result
        let stderrOutput = errorCollector.result

        // Append to generation.log
        let logFile = projectDir.appendingPathComponent("generation.log")
        let separator = "\n" + String(repeating: "=", count: 80) + "\n"
        let header = "DATE: \(Date())\nAGENT: Codex\nPROMPT: \(String(prompt.prefix(200)))\nEXIT: \(exitCode)\(timedOut ? " (WATCHDOG)" : "")\n" + String(repeating: "-", count: 80) + "\n"
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
            onEvent(.error("Process killed by 15-minute watchdog"))
        }
        onEvent(.result(success: exitCode == 0))

        return AgentRunResult(
            success: exitCode == 0,
            output: allOutput,
            error: exitCode == 0 ? nil : timedOut
                ? "Process killed by 15-minute watchdog"
                : stderrOutput.isEmpty
                    ? "Codex exited with code \(exitCode)"
                    : stderrOutput
        )
    }

    // MARK: - Fix

    static func fix(
        errors: String,
        projectDir: URL,
        attempt: Int,
        model: AgentModel,
        onEvent: @escaping @Sendable (AgentEvent) -> Void
    ) async -> AgentRunResult {
        let prompt = """
        Build failed (attempt \(attempt)). Fix ALL errors.
        Read all Source/ files, then fix with targeted edits.

        Errors:
        \(errors)

        Rules: ONLY edit Source/ files. Do NOT touch CMakeLists.txt. C++17, juce:: prefix everywhere,
        juce::Font(juce::FontOptions(float)) not juce::Font(float), .h/.cpp signatures must match.
        Linker errors = your source code, NOT CMakeLists.txt.
        """

        return await run(prompt: prompt, projectDir: projectDir, model: model, onEvent: onEvent)
    }

    // MARK: - Audit

    static func audit(
        projectDir: URL,
        userIntent: String,
        pluginType: String,
        model: AgentModel,
        onEvent: @escaping @Sendable (AgentEvent) -> Void
    ) async -> AgentRunResult {
        let prompt = """
        Audit the plugin code. Read all Source/ files, then fix any issues.

        Check: parameter/UI mismatches, missing juce:: prefixes, .h/.cpp signature mismatches,
        juce::Font(float) (must be juce::FontOptions), LookAndFeel lifecycle, DSP matches "\(userIntent)".
        Plugin type: \(pluginType). Do NOT touch CMakeLists.txt.
        """

        return await run(prompt: prompt, projectDir: projectDir, model: model, onEvent: onEvent)
    }

    // MARK: - Name generation

    static func generatePluginName(
        prompt: String,
        existingNames: Set<String>
    ) async -> String {
        guard let codexPath = DependencyChecker.resolveCommandPath("codex") else {
            return fallbackName(existingNames: existingNames)
        }

        let takenList = existingNames.joined(separator: ", ")
        let namePrompt = """
        Invent a short, creative plugin name (1 word, max 10 chars) for this audio plugin: "\(prompt)".
        The name must sound like a premium audio brand — punchy, evocative, memorable.
        These names are ALREADY TAKEN, do NOT use any of them: [\(takenList)].
        Reply with ONLY the name, nothing else. No quotes, no explanation.
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["--quiet", "--approval-mode", "full-auto", namePrompt]
        process.environment = DependencyChecker.shellEnvironment
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()

            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    c.resume()
                }
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let raw = String(data: data, encoding: .utf8) {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                    .components(separatedBy: .whitespaces).first ?? ""
                if !name.isEmpty && !existingNames.contains(name) {
                    return name
                }
            }
        } catch {}

        return fallbackName(existingNames: existingNames)
    }

    private static func fallbackName(existingNames: Set<String>) -> String {
        let pool = ["Flux", "Apex", "Nova", "Zinc", "Opal", "Noir", "Glow", "Husk", "Dusk", "Null"]
        let takenLower = Set(existingNames.map { $0.lowercased() })
        if let available = pool.first(where: { !takenLower.contains($0.lowercased()) }) {
            return available
        }
        return "Plugin\(UUID().uuidString.prefix(4))"
    }

    // MARK: - Arguments

    /// Builds Codex CLI arguments.
    /// Codex uses `--quiet` for non-interactive mode and writes files directly.
    private static func buildArguments(prompt: String, model: AgentModel) -> [String] {
        [
            "--quiet",
            "--approval-mode", "full-auto",
            "--model", model.cliFlag,
            prompt,
        ]
    }

    // MARK: - Event parser

    /// Parses Codex CLI output into AgentEvents.
    /// Codex outputs JSON lines when using structured output, or plain text otherwise.
    /// We handle both formats gracefully.
    private static func parseEvents(_ line: String) -> [AgentEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Try JSON first (Codex may emit structured events)
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseJSONEvent(json)
        }

        // Fall back to plain text
        return [.text(trimmed)]
    }

    private static func parseJSONEvent(_ json: [String: Any]) -> [AgentEvent] {
        let type = json["type"] as? String ?? ""
        var events: [AgentEvent] = []

        switch type {
        case "message":
            if let content = json["content"] as? String {
                events.append(.text(content))
            }
        case "function_call", "tool_use":
            let name = json["name"] as? String ?? json["function"] as? String ?? "tool"
            let args = json["arguments"] as? [String: Any] ?? json["input"] as? [String: Any] ?? [:]
            let filePath = args["file_path"] as? String ?? args["path"] as? String
            events.append(.toolUse(tool: name, filePath: filePath, detail: nil))
        case "function_call_output", "tool_result":
            let name = json["name"] as? String ?? "tool"
            let output = json["output"] as? String ?? json["content"] as? String ?? ""
            events.append(.toolResult(tool: name, output: output))
        case "error":
            let msg = json["message"] as? String ?? json["error"] as? String ?? "Unknown error"
            events.append(.error(msg))
        default:
            // Try to extract any text content
            if let content = json["content"] as? String, !content.isEmpty {
                events.append(.text(content))
            }
        }

        return events
    }
}

// MARK: - Thread-safe string collector (shared with ClaudeCodeService)

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
