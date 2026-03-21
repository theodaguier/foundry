import Foundation
import SwiftUI

enum GenerationError: Error, LocalizedError {
    case assemblyFailed(String)
    case generationFailed(String)
    case buildFailed(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .assemblyFailed(let msg): "Project assembly failed: \(msg)"
        case .generationFailed(let msg): "Code generation failed: \(msg)"
        case .buildFailed(let msg): msg
        case .installFailed(let msg): "Plugin installation failed: \(msg)"
        }
    }
}

// MARK: - Log

struct PipelineLogLine: Identifiable, Sendable {
    enum Style: Sendable { case normal, success, active, error }
    let id = UUID()
    let timestamp: String
    let message: String
    let style: Style
}

// MARK: - Pipeline

@Observable @MainActor
final class GenerationPipeline {

    var currentStep: GenerationStep = .preparingProject
    var isRunning = false
    var buildAttempt = 0
    var logLines: [PipelineLogLine] = []
    /// Live streaming text from Claude — updated on every delta, shown in real-time in the terminal.
    /// Committed to logLines when Claude starts a new tool use or finishes a content block.
    var streamingText: String = ""
    private var task: Task<Void, Never>?
    private var lastRealEventDate = Date()  // only updated by real Claude events, not the watcher itself
    private var silenceTask: Task<Void, Never>?

    private func log(_ message: String, style: PipelineLogLine.Style = .normal) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        // Skip empty messages and single-char JSON artifacts (], [, {, })
        guard trimmed.count > 1,
              !trimmed.allSatisfy({ "[]{}(),;".contains($0) }) else { return }

        let now = Date()
        let h = Calendar.current.component(.hour, from: now)
        let m = Calendar.current.component(.minute, from: now)
        let s = Calendar.current.component(.second, from: now)
        let ts = String(format: "[%02d:%02d:%02d]", h, m, s)
        logLines.append(PipelineLogLine(timestamp: ts, message: trimmed, style: style))
    }

    /// Watches for silence and logs a "still working…" message every 20s
    private func startSilenceWatcher() {
        silenceTask?.cancel()
        lastRealEventDate = Date()
        silenceTask = Task { [weak self] in
            // Wait a bit before starting to watch — let Claude start first
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled else { return }
                let elapsed = Int(-self.lastRealEventDate.timeIntervalSinceNow)
                if elapsed >= 12 {
                    let now = Date()
                    let h = Calendar.current.component(.hour, from: now)
                    let m = Calendar.current.component(.minute, from: now)
                    let s = Calendar.current.component(.second, from: now)
                    let ts = String(format: "[%02d:%02d:%02d]", h, m, s)
                    self.logLines.append(PipelineLogLine(
                        timestamp: ts,
                        message: "… Claude API computing (\(elapsed)s)",
                        style: .normal
                    ))
                }
            }
        }
    }

    private func stopSilenceWatcher() {
        silenceTask?.cancel()
        silenceTask = nil
    }

    // MARK: - Run

    func run(config: GenerationConfig, appState: AppState) {
        guard !isRunning else { return }

        isRunning = true
        currentStep = .preparingProject
        buildAttempt = 0

        startSilenceWatcher()
        task = Task { [weak self] in
            guard let self else { return }

            do {
                let plugin = try await self.execute(config: config)

                // Add plugin to library
                PluginManager.add(plugin, to: &appState.plugins)

                appState.push(.result(plugin: plugin))
            } catch let error as GenerationError {
                appState.push(.error(message: error.localizedDescription, config: config))
            } catch {
                appState.push(.error(message: error.localizedDescription, config: config))
            }

            self.stopSilenceWatcher()
            self.isRunning = false
        }
    }

    func refine(config: RefineConfig, appState: AppState) {
        guard !isRunning else { return }

        isRunning = true
        currentStep = .generatingDSP
        buildAttempt = 0

        startSilenceWatcher()
        task = Task { [weak self] in
            guard let self else { return }

            do {
                let plugin = try await self.executeRefine(config: config)

                PluginManager.update(plugin, in: &appState.plugins)

                appState.push(.result(plugin: plugin))
            } catch let error as GenerationError {
                // Build a GenerationConfig so the error view can retry
                let genConfig = GenerationConfig(prompt: config.plugin.prompt)
                appState.push(.error(message: error.localizedDescription, config: genConfig))
            } catch {
                let genConfig = GenerationConfig(prompt: config.plugin.prompt)
                appState.push(.error(message: error.localizedDescription, config: genConfig))
            }

            self.stopSilenceWatcher()
            self.isRunning = false
        }
    }

    func cancel() {
        stopSilenceWatcher()
        task?.cancel()
        task = nil
        isRunning = false
    }

    // MARK: - Generate Pipeline

    private func execute(config: GenerationConfig) async throws -> Plugin {
        setStep(.preparingProject)

        let project: ProjectAssembler.AssembledProject
        do {
            project = try ProjectAssembler.assemble(config: config)
        } catch {
            throw GenerationError.assemblyFailed(error.localizedDescription)
        }

        try Task.checkCancellation()

        let callbacks = makeCallbacks()

        setStep(.generatingDSP)

        let pluginRole: String = switch project.pluginType {
        case .instrument: "playable instrument"
        case .effect: "audio effect"
        case .utility: "utility or analysis tool"
        }

        let genPrompt = """
        Build a JUCE \(pluginRole) plugin from scratch: \(config.prompt)

        Read CLAUDE.md first — it is your mission brief and references the knowledge kit files
        in juce-kit/. There are no existing source files — you create everything in Source/.

        Start by reading CLAUDE.md now.
        """
        log("── Claude: Code generation ──", style: .active)
        let genResult = await ClaudeCodeService.run(
            prompt: genPrompt,
            projectDir: project.directory,
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.handleClaudeEvent(event)
                }
            }
        )

        if isAIInfrastructureFailure(genResult.error) {
            throw GenerationError.generationFailed(genResult.error ?? "Claude Code CLI is unavailable")
        }

        // Check that Claude created the source files
        let processorFile = project.directory.appendingPathComponent("Source/PluginProcessor.cpp")
        let editorFile = project.directory.appendingPathComponent("Source/PluginEditor.cpp")
        let processorExists = FileManager.default.fileExists(atPath: processorFile.path)
        let editorExists = FileManager.default.fileExists(atPath: editorFile.path)

        if !processorExists || !editorExists {
            throw GenerationError.generationFailed("Claude did not create the required source files")
        }

        try Task.checkCancellation()

        // Phase 3: Audit pass — Claude reviews its own code before build
        setStep(.generatingUI)
        log("── Claude: Audit pass ──", style: .active)
        let _ = await ClaudeCodeService.audit(
            projectDir: project.directory,
            userIntent: config.prompt,
            pluginType: pluginRole,
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.handleClaudeEvent(event)
                }
            }
        )

        try Task.checkCancellation()

        // Phase 4: Build loop — compiler is the only judge
        setStep(.compiling)
        try await BuildLoop.run(projectDir: project.directory, callbacks: callbacks)

        try Task.checkCancellation()

        setStep(.installing)

        let formats = resolveFormats(config.format)
        let installPaths: Plugin.InstallPaths
        do {
            installPaths = try PluginManager.installPlugin(
                buildDir: project.directory,
                name: project.pluginName,
                formats: formats
            )
        } catch {
            throw GenerationError.installFailed(error.localizedDescription)
        }

        let colors = ["#C8C4BC", "#A8B4A0", "#B0A898", "#9CAAB8", "#B8A8B0", "#A0A8B0"]
        let iconColor = colors.randomElement()!
        let pluginID = UUID()

        // Persist generation log to AppSupport before temp dir is cleaned up
        let tempLog = project.directory.appendingPathComponent("generation.log")
        var generationLogPath: String? = nil
        if FileManager.default.fileExists(atPath: tempLog.path) {
            let logsDir = FoundryPaths.generationLogsDirectory
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            let destLog = FoundryPaths.generationLogFile(for: pluginID)
            try? FileManager.default.copyItem(at: tempLog, to: destLog)
            generationLogPath = destLog.path
        }

        let plugin = Plugin(
            id: pluginID,
            name: project.pluginName,
            type: project.pluginType,
            prompt: config.prompt,
            createdAt: Date(),
            formats: formats,
            installPaths: installPaths,
            iconColor: iconColor,
            status: .installed,
            buildDirectory: project.directory.path,
            generationLogPath: generationLogPath
        )

        BuildDirectoryCleaner.cleanAfterInstall(project.directory)

        return plugin
    }

    // MARK: - Refine Pipeline

    private func executeRefine(config: RefineConfig) async throws -> Plugin {
        guard let buildDir = config.plugin.buildDirectory else {
            throw GenerationError.assemblyFailed("No build directory found - cannot refine this plugin")
        }

        let projectDir = URL(fileURLWithPath: buildDir)

        guard FileManager.default.fileExists(atPath: buildDir) else {
            throw GenerationError.assemblyFailed("Build directory no longer exists: \(buildDir)")
        }

        let callbacks = makeCallbacks()

        setStep(.generatingDSP)

        let pluginRole: String = switch config.plugin.type {
        case .instrument: "playable instrument"
        case .effect: "audio effect"
        case .utility: "utility or analysis tool"
        }
        let refinePrompt = """
        You are modifying an existing JUCE \(pluginRole) plugin. Use your tools to read and edit files directly.

        Read these source files first:
        1. Source/PluginProcessor.h
        2. Source/PluginProcessor.cpp
        3. Source/PluginEditor.h
        4. Source/PluginEditor.cpp

        The user wants this modification: \(config.modification)

        Use your Edit tool to make targeted changes. Keep everything else working.
        Do NOT rewrite files from scratch — only change what's needed.
        Keep class names unchanged. The plugin must compile with C++17 and JUCE.
        """

        let genResult = await ClaudeCodeService.run(
            prompt: refinePrompt,
            projectDir: projectDir,
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.handleClaudeEvent(event)
                }
            }
        )

        if isAIInfrastructureFailure(genResult.error) {
            throw GenerationError.generationFailed(genResult.error ?? "Claude Code CLI is unavailable")
        }

        if !genResult.success {
            let processorFile = projectDir.appendingPathComponent("Source/PluginProcessor.cpp")
            let processorContent = (try? String(contentsOf: processorFile, encoding: .utf8)) ?? ""
            if processorContent.isEmpty {
                throw GenerationError.generationFailed(genResult.error ?? "Claude did not modify the code")
            }
        }

        try Task.checkCancellation()

        setStep(.compiling)
        try await BuildLoop.run(projectDir: projectDir, callbacks: callbacks)

        try Task.checkCancellation()

        setStep(.installing)

        let formats = config.plugin.formats
        let installPaths: Plugin.InstallPaths
        do {
            installPaths = try PluginManager.installPlugin(
                buildDir: projectDir,
                name: config.plugin.name,
                formats: formats
            )
        } catch {
            throw GenerationError.installFailed(error.localizedDescription)
        }

        // Persist generation log to AppSupport before returning
        let tempLog = projectDir.appendingPathComponent("generation.log")
        let logsDir = FoundryPaths.generationLogsDirectory
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: tempLog.path) {
            let destLog = FoundryPaths.generationLogFile(for: config.plugin.id)
            // Overwrite previous log (refine replaces the last generation)
            try? FileManager.default.removeItem(at: destLog)
            try? FileManager.default.copyItem(at: tempLog, to: destLog)
        }

        // Return updated plugin, preserving identity
        var updated = config.plugin
        updated.installPaths = installPaths
        updated.prompt = config.plugin.prompt + "\n-> " + config.modification
        updated.status = .installed
        updated.generationLogPath = FoundryPaths.generationLogFile(for: config.plugin.id).path

        return updated
    }

    // MARK: - Helpers

    private func setStep(_ step: GenerationStep) {
        let prev = currentStep
        currentStep = step
        if step != prev {
            let completionMap: [GenerationStep: String] = [
                .preparingProject: "PREPARING PROJECT: Dependencies resolved.",
                .generatingDSP: "GENERATING DSP: Audio kernel convergence complete.",
                .generatingUI: "GENERATING UI: Interface layer committed.",
                .compiling: "COMPILING: Build artifacts ready.",
                .installing: "INSTALLING: Plugin bundle staged.",
            ]
            if let msg = completionMap[prev] {
                log(msg, style: .success)
            }
            log("START: \(step.logLabel)...", style: .active)
        }
    }

    private func handleClaudeEvent(_ event: ClaudeCodeService.ClaudeEvent) {
        lastRealEventDate = Date()

        switch event {

        case .toolUse(let tool, let filePath, let detail):
            let t = tool.lowercased()
            let filename = filePath ?? filePath.map { URL(fileURLWithPath: $0).lastPathComponent }

            if t == "write_complete" {
                let target = filePath ?? "file"
                let suffix = detail.map { " (\($0))" } ?? ""
                log("✓ WRITE \(target)\(suffix)", style: .normal)
                if let p = filePath {
                    if p.contains("Processor") { setStep(.generatingDSP) }
                    else if p.contains("Editor") || p.contains("LookAndFeel") { setStep(.generatingUI) }
                }

            } else if t.contains("write") {
                let target = filePath ?? "…"
                let suffix = detail.map { " \($0)" } ?? ""
                log("WRITE \(target)\(suffix)", style: .normal)
                if let p = filePath {
                    if p.contains("Processor") { setStep(.generatingDSP) }
                    else if p.contains("Editor") || p.contains("LookAndFeel") { setStep(.generatingUI) }
                }

            } else if t.contains("edit") || t.contains("str_replace") || t.contains("multiedit") || t.contains("multi_edit") {
                let target = filePath ?? "file"
                let suffix = detail.map { " \($0)" } ?? ""
                log("EDIT \(target)\(suffix)", style: .normal)
                if let p = filePath {
                    if p.contains("Processor") { setStep(.generatingDSP) }
                    else if p.contains("Editor") || p.contains("LookAndFeel") { setStep(.generatingUI) }
                }

            } else if t.contains("read") {
                if let name = filename { log("READ \(name)", style: .normal) }

            } else if t.contains("bash") || t.contains("execute") {
                if let cmd = detail { log("$ \(cmd)", style: .normal) }

            } else if t == "starting…" || detail == "starting…" {
                log("\(tool.uppercased()) …", style: .normal)
            }

        case .toolResult(let tool, let output):
            let t = tool.lowercased()
            let isBash = t.contains("bash") || t.contains("execute") || t.contains("run")
            let isRead = t.contains("read") || t.contains("view")

            if isBash {
                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { log(trimmed, style: .normal) }
                }
            } else if isRead {
                let lines = output.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                for line in lines.prefix(8) { log("  \(line)", style: .normal) }
                if lines.count > 8 { log("  … (\(lines.count) lines total)", style: .normal) }
            } else {
                let lines = output.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                for line in lines.suffix(4) { log(line, style: .normal) }
            }

        case .text(let t):
            for line in t.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count > 2 else { continue }
                log(trimmed, style: .normal)
            }

        case .error(let msg):
            log("ERROR: \(msg)", style: .error)

        case .result(let success):
            if !success {
                log("Claude run ended with errors", style: .active)
            }
        }
    }

    private func resolveFormats(_ option: FormatOption) -> [PluginFormat] {
        switch option {
        case .au: [.au]
        case .vst3: [.vst3]
        case .both: [.au, .vst3]
        }
    }

    private func isAIInfrastructureFailure(_ message: String?) -> Bool {
        guard let message else { return false }
        let lowercased = message.lowercased()
        return lowercased.contains("not available in foundry's runtime environment")
            || lowercased.contains("failed to launch claude code")
            || lowercased.contains("command not found")
    }

    private func makeCallbacks() -> PipelineCallbacks {
        PipelineCallbacks(
            onBuildAttempt: { [weak self] attempt in
                self?.buildAttempt = attempt
            },
            onStepChange: { [weak self] step in
                self?.setStep(step)
            },
            onClaudeEvent: { [weak self] event in
                self?.handleClaudeEvent(event)
            }
        )
    }
}
