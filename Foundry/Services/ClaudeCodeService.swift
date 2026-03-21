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

    /// 15-minute watchdog — safety net for silent crashes, not a functional timeout.
    /// Claude advances the pipeline via the `result` event; this only fires if something hangs.
    private static let watchdogSeconds = 900

    // MARK: - Generate

    static func run(
        prompt: String,
        projectDir: URL,
        model: AgentModel,
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
        process.arguments = Self.buildArguments(prompt: prompt, model: model)

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

        // 15-minute watchdog — safety net only. Claude emits a `result` event when done,
        // which causes waitUntilExit to return naturally. This timer only fires if the
        // process hangs silently (crash, deadlock, etc.).
        let watchdog = DispatchSource.makeTimerSource(queue: .global())
        watchdog.schedule(deadline: .now() + .seconds(watchdogSeconds))
        watchdog.setEventHandler { [process] in
            if process.isRunning {
                process.terminate()
            }
        }
        watchdog.resume()

        // Block a background thread until process exits
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                c.resume()
            }
        }

        watchdog.cancel()

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
        let header = "DATE: \(Date())\nPROMPT: \(String(prompt.prefix(200)))\nEXIT: \(exitCode)\(timedOut ? " (WATCHDOG)" : "")\n" + String(repeating: "-", count: 80) + "\n"
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

        return RunResult(
            success: exitCode == 0,
            output: allOutput,
            error: exitCode == 0 ? nil : timedOut
                ? "Process killed by 15-minute watchdog"
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
        model: AgentModel,
        onEvent: @escaping @Sendable (ClaudeEvent) -> Void
    ) async -> RunResult {
        let prompt = """
        Build failed (attempt \(attempt)). Fix ALL errors in 3 turns max.
        Turn 1: Read ALL Source/ files in PARALLEL.
        Turn 2: Fix with PARALLEL Edit calls.
        Turn 3: Only if needed.

        Errors:
        \(errors)

        Rules: ONLY edit Source/ files. Do NOT touch CMakeLists.txt. C++17, juce:: prefix everywhere,
        juce::Font(juce::FontOptions(float)) not juce::Font(float), .h/.cpp signatures must match.
        Linker errors = your source code, NOT CMakeLists.txt.
        """

        return await run(
            prompt: prompt,
            projectDir: projectDir,
            model: model,
            onEvent: onEvent
        )
    }

    /// Runs Claude Code to audit and fix generated code before build
    static func audit(
        projectDir: URL,
        userIntent: String,
        pluginType: String,
        model: AgentModel,
        onEvent: @escaping @Sendable (ClaudeEvent) -> Void
    ) async -> RunResult {
        let prompt = """
        Audit the plugin code. SPEED IS CRITICAL — do this in 3 turns max.
        Turn 1: Read ALL 5 Source/ files in PARALLEL.
        Turn 2: Fix any issues with PARALLEL Edit calls.
        Turn 3: Only if needed.

        Check: parameter/UI mismatches, missing juce:: prefixes, .h/.cpp signature mismatches,
        juce::Font(float) (must be juce::FontOptions), LookAndFeel lifecycle, DSP matches "\(userIntent)".
        Plugin type: \(pluginType). Do NOT touch CMakeLists.txt.
        """

        return await run(
            prompt: prompt,
            projectDir: projectDir,
            model: model,
            onEvent: onEvent
        )
    }

    // MARK: - Name generation

    static func generatePluginName(
        prompt: String,
        existingNames: Set<String>
    ) async -> String {
        guard let claudePath = DependencyChecker.resolveCommandPath("claude") else {
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
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = [
            "-p", namePrompt,
            "--dangerously-skip-permissions",
            "--output-format", "text",
            "--max-turns", "1",
            "--model", "haiku",
        ]
        process.environment = DependencyChecker.shellEnvironment
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

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

    // MARK: - Argument builder

    static func buildArguments(prompt: String, model: AgentModel) -> [String] {
        [
            "-p",
            prompt,
            "--dangerously-skip-permissions",
            "--output-format", "stream-json",
            "--verbose",
            "--max-turns", "25",
            "--model", model.cliFlag,
            "--strict-mcp-config",
            "--disallowedTools", "Bash,Grep,Glob,WebSearch,WebFetch,NotebookEdit,Skill,EnterPlanMode,ExitPlanMode,EnterWorktree,ExitWorktree,CronCreate,CronDelete,CronList,Task,TaskCreate,TaskGet,TaskUpdate,TaskList,TaskOutput,TaskStop,AskUserQuestion,ToolSearch",
            "--append-system-prompt",
            """
            SPEED IS CRITICAL. Minimize the number of turns.
            Turn 1: Read CLAUDE.md AND all juce-kit/*.md files in PARALLEL (one Read call per file, all in the same turn).
            Turn 2-4: Write ALL 5 source files. Use PARALLEL Write calls — write multiple files in the same turn.
            Do NOT verify your work with extra Read calls after writing. Trust your output.
            Never respond with only text — always use tools.
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
            let output = extractToolOutput(from: json)
            let toolName = json["tool_name"] as? String ?? json["name"] as? String ?? "tool"
            if !output.isEmpty {
                events.append(.toolResult(tool: toolName, output: output))
            }

        case "result":
            let isError = json["is_error"] as? Bool ?? false
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

// MARK: - AgentService bridge

extension ClaudeCodeService {

    /// Converts ClaudeEvent → AgentEvent.
    private static func bridgeEvent(_ event: ClaudeEvent) -> AgentEvent {
        switch event {
        case .toolUse(let tool, let filePath, let detail):
            return .toolUse(tool: tool, filePath: filePath, detail: detail)
        case .toolResult(let tool, let output):
            return .toolResult(tool: tool, output: output)
        case .text(let t):
            return .text(t)
        case .result(let success):
            return .result(success: success)
        case .error(let msg):
            return .error(msg)
        }
    }

    private static func bridgeResult(_ r: RunResult) -> AgentRunResult {
        AgentRunResult(success: r.success, output: r.output, error: r.error)
    }

    static func agentRun(
        prompt: String,
        projectDir: URL,
        model: AgentModel,
        onEvent: @escaping @Sendable (AgentEvent) -> Void
    ) async -> AgentRunResult {
        bridgeResult(await run(prompt: prompt, projectDir: projectDir, model: model) { onEvent(bridgeEvent($0)) })
    }

    static func agentFix(
        errors: String,
        projectDir: URL,
        attempt: Int,
        model: AgentModel,
        onEvent: @escaping @Sendable (AgentEvent) -> Void
    ) async -> AgentRunResult {
        bridgeResult(await fix(errors: errors, projectDir: projectDir, attempt: attempt, model: model) { onEvent(bridgeEvent($0)) })
    }

    static func agentAudit(
        projectDir: URL,
        userIntent: String,
        pluginType: String,
        model: AgentModel,
        onEvent: @escaping @Sendable (AgentEvent) -> Void
    ) async -> AgentRunResult {
        bridgeResult(await audit(projectDir: projectDir, userIntent: userIntent, pluginType: pluginType, model: model) { onEvent(bridgeEvent($0)) })
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
