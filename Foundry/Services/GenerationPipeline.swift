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
    /// The AI-generated plugin name — set during the preparingProject step.
    var generatedPluginName: String?
    private var task: Task<Void, Never>?
    private var lastRealEventDate = Date()  // only updated by real Claude events, not the watcher itself
    private var silenceTask: Task<Void, Never>?
    private weak var appStateRef: AppState?

    /// The telemetry builder for the current generation, accessible for the UI.
    var lastTelemetryId: UUID?

    private var telemetry: TelemetryBuilder?

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
                        message: "… Agent computing (\(elapsed)s)",
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

        appStateRef = appState
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

                appState.finishBuild()
                appState.push(.result(plugin: plugin))
            } catch is CancellationError {
                // User cancelled — save telemetry with cancelled outcome
                if let tb = self.telemetry {
                    tb.outcome = .cancelled
                    self.saveTelemetry(tb)
                }
                self.stopSilenceWatcher()
                self.isRunning = false
                return
            } catch let error as GenerationError {
                appState.finishBuild()
                appState.push(.error(message: error.localizedDescription, config: config))
            } catch {
                appState.finishBuild()
                appState.push(.error(message: error.localizedDescription, config: config))
            }

            self.stopSilenceWatcher()
            self.isRunning = false
        }
    }

    func refine(config: RefineConfig, appState: AppState) {
        guard !isRunning else { return }

        appStateRef = appState
        isRunning = true
        currentStep = .generatingDSP
        buildAttempt = 0

        startSilenceWatcher()
        task = Task { [weak self] in
            guard let self else { return }

            do {
                let plugin = try await self.executeRefine(config: config)

                PluginManager.update(plugin, in: &appState.plugins)

                appState.finishBuild()
                appState.push(.result(plugin: plugin))
            } catch is CancellationError {
                if let tb = self.telemetry {
                    tb.outcome = .cancelled
                    self.saveTelemetry(tb)
                }
                self.stopSilenceWatcher()
                self.isRunning = false
                return
            } catch let error as GenerationError {
                let genConfig = GenerationConfig(prompt: config.plugin.prompt)
                appState.finishBuild()
                appState.push(.error(message: error.localizedDescription, config: genConfig))
            } catch {
                let genConfig = GenerationConfig(prompt: config.plugin.prompt)
                appState.finishBuild()
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
        // Initialize telemetry
        let tb = TelemetryBuilder()
        telemetry = tb
        tb.agent = config.agent
        tb.model = config.model.id
        tb.originalPrompt = config.prompt
        tb.pluginType = ProjectAssembler.inferPluginType(from: config.prompt)
        tb.format = config.format
        tb.channelLayout = config.channelLayout
        tb.presetCount = config.presetCount.rawValue
        tb.xcodeVersion = TelemetryService.detectXcodeVersion()
        tb.agentCLIVersion = TelemetryService.detectAgentCLIVersion(agent: config.agent)

        setStep(.preparingProject)

        let existingNames = Set((appStateRef?.plugins ?? []).map(\.name))
        let pluginName = await AgentResolver.generatePluginName(
            agent: config.agent,
            prompt: config.prompt,
            existingNames: existingNames
        )
        generatedPluginName = pluginName

        let project: ProjectAssembler.AssembledProject
        do {
            project = try ProjectAssembler.assemble(config: config, pluginName: pluginName)
        } catch {
            tb.outcome = .failedGeneration
            tb.failureStage = .assembly
            tb.failureMessage = error.localizedDescription
            saveTelemetry(tb)
            throw GenerationError.assemblyFailed(error.localizedDescription)
        }

        try Task.checkCancellation()

        let callbacks = makeCallbacks()

        setStep(.generatingDSP)
        tb.generationStart = Date()

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
        log("── \(config.agent.rawValue) · \(config.model.displayName): Code generation ──", style: .active)
        let genResult = await AgentResolver.run(
            agent: config.agent,
            model: config.model,
            prompt: genPrompt,
            projectDir: project.directory,
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.handleAgentEvent(event)
                }
            }
        )
        tb.generationEnd = Date()
        if let usage = genResult.tokenUsage { tb.tokenUsage.add(usage) }

        if isAIInfrastructureFailure(genResult.error) {
            tb.outcome = .failedGeneration
            tb.failureStage = .generation
            tb.failureMessage = genResult.error
            saveTelemetry(tb)
            throw GenerationError.generationFailed(genResult.error ?? "Claude Code CLI is unavailable")
        }

        // Check that Claude created the source files
        let processorFile = project.directory.appendingPathComponent("Source/PluginProcessor.cpp")
        let editorFile = project.directory.appendingPathComponent("Source/PluginEditor.cpp")
        let processorExists = FileManager.default.fileExists(atPath: processorFile.path)
        let editorExists = FileManager.default.fileExists(atPath: editorFile.path)

        if !processorExists || !editorExists {
            tb.outcome = .failedGeneration
            tb.failureStage = .generation
            tb.failureMessage = "Claude did not create the required source files"
            saveTelemetry(tb)
            throw GenerationError.generationFailed("Claude did not create the required source files")
        }

        try Task.checkCancellation()

        // Phase 3: Audit pass — agent reviews its own code before build
        setStep(.generatingUI)
        tb.auditStart = Date()
        log("── \(config.agent.rawValue) · \(config.model.displayName): Audit pass ──", style: .active)
        let auditResult = await AgentResolver.audit(
            agent: config.agent,
            model: config.model,
            projectDir: project.directory,
            userIntent: config.prompt,
            pluginType: pluginRole,
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.handleAgentEvent(event)
                }
            }
        )
        tb.auditEnd = Date()
        if let usage = auditResult.tokenUsage { tb.tokenUsage.add(usage) }

        try Task.checkCancellation()

        // Phase 4: Build loop — compiler is the only judge
        setStep(.compiling)
        tb.buildStart = Date()
        do {
            try await BuildLoop.run(projectDir: project.directory, agent: config.agent, model: config.model, callbacks: callbacks, telemetry: tb)
        } catch let error as GenerationError {
            tb.buildEnd = Date()
            tb.outcome = .failedBuild
            tb.failureStage = .build
            tb.failureMessage = error.localizedDescription
            saveTelemetry(tb)
            throw error
        }
        tb.buildEnd = Date()

        try Task.checkCancellation()

        setStep(.installing)
        tb.installStart = Date()

        let formats = resolveFormats(config.format)
        let installPaths: Plugin.InstallPaths
        do {
            installPaths = try PluginManager.installPlugin(
                buildDir: project.directory,
                name: project.pluginName,
                formats: formats
            )
        } catch {
            tb.installEnd = Date()
            tb.outcome = .failedInstall
            tb.failureStage = .install
            tb.failureMessage = error.localizedDescription
            saveTelemetry(tb)
            throw GenerationError.installFailed(error.localizedDescription)
        }
        tb.installEnd = Date()

        let colors = ["#C8C4BC", "#A8B4A0", "#B0A898", "#9CAAB8", "#B8A8B0", "#A0A8B0"]
        let iconColor = colors.randomElement()!
        let pluginID = UUID()

        // Finalize telemetry
        tb.pluginId = pluginID
        tb.versionNumber = 1
        tb.outcome = .success
        saveTelemetry(tb)

        // Archive build directory to versioned storage before cleanup
        let archivedBuildDir: String?
        do {
            archivedBuildDir = try PluginManager.archiveBuild(
                from: project.directory,
                pluginID: pluginID,
                version: 1
            )
        } catch {
            print("[Pipeline] Failed to archive build: \(error)")
            archivedBuildDir = nil
        }

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

        let version = PluginVersion(
            id: UUID(),
            pluginId: pluginID,
            versionNumber: 1,
            prompt: config.prompt,
            createdAt: Date(),
            buildDirectory: archivedBuildDir,
            installPaths: installPaths,
            iconColor: iconColor,
            isActive: true,
            agent: config.agent,
            model: config.model,
            telemetryId: tb.id
        )

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
            buildDirectory: archivedBuildDir,
            generationLogPath: generationLogPath,
            agent: config.agent,
            model: config.model,
            currentVersion: 1,
            versions: [version]
        )

        BuildDirectoryCleaner.cleanAfterInstall(project.directory)

        return plugin
    }

    // MARK: - Refine Pipeline

    private func executeRefine(config: RefineConfig) async throws -> Plugin {
        // Initialize telemetry
        let tb = TelemetryBuilder()
        telemetry = tb
        let agent = config.plugin.agent ?? .claudeCode
        let model = config.plugin.model ?? agent.defaultModel
        tb.agent = agent
        tb.model = model.id
        tb.originalPrompt = config.modification
        tb.pluginType = config.plugin.type
        tb.format = config.plugin.formats.count > 1 ? .both : (config.plugin.formats.first == .au ? .au : .vst3)
        tb.xcodeVersion = TelemetryService.detectXcodeVersion()
        tb.agentCLIVersion = TelemetryService.detectAgentCLIVersion(agent: agent)

        guard let buildDir = config.plugin.buildDirectory else {
            tb.outcome = .failedGeneration
            tb.failureStage = .assembly
            tb.failureMessage = "No build directory found"
            saveTelemetry(tb)
            throw GenerationError.assemblyFailed("No build directory found - cannot refine this plugin")
        }

        let archivedDir = URL(fileURLWithPath: buildDir)

        guard FileManager.default.fileExists(atPath: buildDir) else {
            tb.outcome = .failedGeneration
            tb.failureStage = .assembly
            tb.failureMessage = "Build directory no longer exists"
            saveTelemetry(tb)
            throw GenerationError.assemblyFailed("Build directory no longer exists: \(buildDir)")
        }

        // Copy archived build to a fresh temp directory for refining
        let uuid = UUID().uuidString.prefix(8).lowercased()
        let projectDir = URL(fileURLWithPath: "/tmp/foundry-build-\(uuid)")
        do {
            try FileManager.default.copyItem(at: archivedDir, to: projectDir)
        } catch {
            tb.outcome = .failedGeneration
            tb.failureStage = .assembly
            tb.failureMessage = error.localizedDescription
            saveTelemetry(tb)
            throw GenerationError.assemblyFailed("Failed to restore build for refining: \(error.localizedDescription)")
        }

        // Lock CMakeLists.txt so Claude cannot modify it (prevents plugin rename)
        let cmakePath = projectDir.appendingPathComponent("CMakeLists.txt").path
        try? FileManager.default.setAttributes(
            [.immutable: true],
            ofItemAtPath: cmakePath
        )

        let callbacks = makeCallbacks()

        setStep(.generatingDSP)
        tb.generationStart = Date()

        let pluginRole: String = switch config.plugin.type {
        case .instrument: "playable instrument"
        case .effect: "audio effect"
        case .utility: "utility or analysis tool"
        }

        let refinePrompt = """
        You are refining an existing, working JUCE \(pluginRole) plugin called "\(config.plugin.name)".
        The plugin already compiles and runs. Your job is to make a targeted modification — not rebuild it.

        ## Rules
        - Do NOT modify CMakeLists.txt — it is locked.
        - Do NOT rename the plugin or change class names (\(config.plugin.name)Processor, \(config.plugin.name)Editor).
        - Do NOT create new files — only edit existing Source/ files.
        - Do NOT rewrite entire files — use Edit to change only what's needed.
        - Keep all existing functionality intact unless the modification explicitly replaces it.

        ## Existing source files (read ALL of these first)
        - Source/PluginProcessor.h
        - Source/PluginProcessor.cpp
        - Source/PluginEditor.h
        - Source/PluginEditor.cpp
        - Source/FoundryLookAndFeel.h

        ## Reference
        The juce-kit/ folder contains API and pattern references if you need them.

        ## Requested modification
        \(config.modification)

        ## Checklist before you finish
        - Every new parameter has a matching UI control with addAndMakeVisible() and an Attachment
        - Every removed parameter has its UI control removed too
        - Header (.h) and implementation (.cpp) signatures match exactly
        - All JUCE types are fully qualified (juce::Slider, juce::AudioProcessorValueTreeState, etc.)
        - The plugin compiles with C++17 and links against juce_audio_utils + juce_dsp
        """

        let genResult = await AgentResolver.run(
            agent: agent,
            model: model,
            prompt: refinePrompt,
            projectDir: projectDir,
            isRefine: true,
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.handleAgentEvent(event)
                }
            }
        )
        tb.generationEnd = Date()
        if let usage = genResult.tokenUsage { tb.tokenUsage.add(usage) }

        if isAIInfrastructureFailure(genResult.error) {
            tb.outcome = .failedGeneration
            tb.failureStage = .generation
            tb.failureMessage = genResult.error
            saveTelemetry(tb)
            throw GenerationError.generationFailed(genResult.error ?? "Claude Code CLI is unavailable")
        }

        if !genResult.success {
            let processorFile = projectDir.appendingPathComponent("Source/PluginProcessor.cpp")
            let processorContent = (try? String(contentsOf: processorFile, encoding: .utf8)) ?? ""
            if processorContent.isEmpty {
                tb.outcome = .failedGeneration
                tb.failureStage = .generation
                tb.failureMessage = genResult.error ?? "Claude did not modify the code"
                saveTelemetry(tb)
                throw GenerationError.generationFailed(genResult.error ?? "Claude did not modify the code")
            }
        }

        try Task.checkCancellation()

        // Unlock CMakeLists.txt before build (cmake needs to read it)
        try? FileManager.default.setAttributes(
            [.immutable: false],
            ofItemAtPath: cmakePath
        )

        setStep(.compiling)
        tb.buildStart = Date()
        do {
            try await BuildLoop.run(projectDir: projectDir, agent: agent, model: model, callbacks: callbacks, telemetry: tb)
        } catch let error as GenerationError {
            tb.buildEnd = Date()
            tb.outcome = .failedBuild
            tb.failureStage = .build
            tb.failureMessage = error.localizedDescription
            saveTelemetry(tb)
            throw error
        }
        tb.buildEnd = Date()

        try Task.checkCancellation()

        setStep(.installing)
        tb.installStart = Date()

        // Uninstall old version first to prevent conflicts
        try? PluginManager.uninstallPlugin(config.plugin)

        let formats = config.plugin.formats
        let installPaths: Plugin.InstallPaths
        do {
            installPaths = try PluginManager.installPlugin(
                buildDir: projectDir,
                name: config.plugin.name,
                formats: formats
            )
        } catch {
            tb.installEnd = Date()
            tb.outcome = .failedInstall
            tb.failureStage = .install
            tb.failureMessage = error.localizedDescription
            saveTelemetry(tb)
            throw GenerationError.installFailed(error.localizedDescription)
        }
        tb.installEnd = Date()

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

        // Create new version
        let versionNumber = config.plugin.nextVersionNumber

        // Finalize telemetry
        tb.pluginId = config.plugin.id
        tb.versionNumber = versionNumber
        tb.outcome = .success
        saveTelemetry(tb)

        let archivedBuildDir: String?
        do {
            archivedBuildDir = try PluginManager.archiveBuild(
                from: projectDir,
                pluginID: config.plugin.id,
                version: versionNumber
            )
        } catch {
            print("[Pipeline] Failed to archive refine build: \(error)")
            archivedBuildDir = nil
        }

        let newVersion = PluginVersion(
            id: UUID(),
            pluginId: config.plugin.id,
            versionNumber: versionNumber,
            prompt: config.modification,
            createdAt: Date(),
            buildDirectory: archivedBuildDir,
            installPaths: installPaths,
            iconColor: config.plugin.iconColor,
            isActive: true,
            agent: agent,
            model: model,
            telemetryId: tb.id
        )

        // Return updated plugin, preserving identity
        var updated = config.plugin
        updated.installPaths = installPaths
        updated.prompt = config.plugin.prompt + "\n-> " + config.modification
        updated.status = .installed
        updated.generationLogPath = FoundryPaths.generationLogFile(for: config.plugin.id).path
        updated.buildDirectory = archivedBuildDir
        updated.currentVersion = versionNumber

        // Deactivate previous versions
        var versions = updated.versions.map { v -> PluginVersion in
            var copy = v
            copy.isActive = false
            return copy
        }
        versions.append(newVersion)
        updated.versions = versions

        // Clean up the temp working directory
        BuildDirectoryCleaner.cleanAfterInstall(projectDir)

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

            // Keep global progress in sync even when the generation view isn't visible
            if let appState = appStateRef, let build = appState.activeBuild {
                build.updateStep(from: prev, to: step)
                appState.buildProgress = build.progress
            }
        }
    }

    private func handleAgentEvent(_ event: AgentEvent) {
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
                log("Agent run ended with errors", style: .active)
            }
        }
    }

    private func saveTelemetry(_ tb: TelemetryBuilder) {
        let record = tb.build()
        lastTelemetryId = record.id
        TelemetryService.save(record)
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
            || lowercased.contains("failed to launch codex")
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
            onAgentEvent: { [weak self] event in
                self?.handleAgentEvent(event)
            }
        )
    }
}
