import Foundation
import SwiftUI

enum GenerationError: Error, LocalizedError {
    case assemblyFailed(String)
    case generationFailed(String)
    case buildFailed(String)
    case installFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .assemblyFailed(let msg): "Project assembly failed: \(msg)"
        case .generationFailed(let msg): "Code generation failed: \(msg)"
        case .buildFailed(let msg): msg
        case .installFailed(let msg): "Plugin installation failed: \(msg)"
        case .timeout: "Generation timed out"
        }
    }
}

// MARK: - Log

struct PipelineLogLine: Identifiable, Sendable {
    enum Style: Sendable { case normal, success, active }
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
    private var task: Task<Void, Never>?

    private func log(_ message: String, style: PipelineLogLine.Style = .normal) {
        let now = Date()
        let h = Calendar.current.component(.hour, from: now)
        let m = Calendar.current.component(.minute, from: now)
        let s = Calendar.current.component(.second, from: now)
        let ts = String(format: "[%02d:%02d:%02d]", h, m, s)
        logLines.append(PipelineLogLine(timestamp: ts, message: message, style: style))
    }

    // MARK: - Run

    func run(config: GenerationConfig, appState: AppState) {
        guard !isRunning else { return }

        isRunning = true
        currentStep = .preparingProject
        buildAttempt = 0

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

            self.isRunning = false
        }
    }

    func refine(config: RefineConfig, appState: AppState) {
        guard !isRunning else { return }

        isRunning = true
        currentStep = .generatingDSP
        buildAttempt = 0

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

            self.isRunning = false
        }
    }

    func cancel() {
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
        let initialEditorSnapshot = captureEditorSnapshot(in: project.directory)

        setStep(.generatingDSP)

        let pluginRole: String = switch project.pluginType {
        case .instrument: "playable instrument"
        case .effect: "audio effect"
        case .utility: "utility or analysis tool"
        }
        let presetCount = config.presetCount.rawValue
        let presetInstruction = presetCount > 0
            ? "\n- Implement exactly \(presetCount) presets with a ComboBox selector in the UI (see CLAUDE.md Presets section)"
            : ""
        let genPrompt = """
        Build a JUCE \(pluginRole) plugin: \(config.prompt)

        Follow the implementation guide in CLAUDE.md exactly. It contains everything you need:
        architecture, DSP patterns, UI wiring, validation criteria, and fatal mistakes to avoid.

        ## Your workflow:
        1. Read CLAUDE.md (your expert reference — read it fully before writing any code)
        2. Read all Source/ files to understand the stubs
        3. Follow Phases 1→2→3→4 from CLAUDE.md in strict order\(presetInstruction.isEmpty ? "" : "\n        4. Phase 5: Presets (see CLAUDE.md)")
        4. Use Edit to modify existing methods — never add duplicate definitions

        Start by reading CLAUDE.md now.
        """
        let genResult = await ClaudeCodeService.run(
            prompt: genPrompt,
            projectDir: project.directory,
            timeoutSeconds: 300,
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.handleClaudeEvent(event)
                }
            }
        )

        if isAIInfrastructureFailure(genResult.error) {
            throw GenerationError.generationFailed(genResult.error ?? "Claude Code CLI is unavailable")
        }

        // Capture initial file snapshots to detect if Claude modified them.
        // The stubs now contain a minimal viable implementation (parameters, DSP, UI)
        // so even if Claude does nothing, the plugin compiles and passes validation.
        // But we still want Claude to customize the plugin for the user's prompt.
        let processorFile = project.directory.appendingPathComponent("Source/PluginProcessor.cpp")
        let editorFile = project.directory.appendingPathComponent("Source/PluginEditor.cpp")
        let initialProcessor = (try? String(contentsOf: processorFile, encoding: .utf8)) ?? ""
        let initialEditor = (try? String(contentsOf: editorFile, encoding: .utf8)) ?? ""

        func filesWereModified() -> Bool {
            let currentProcessor = (try? String(contentsOf: processorFile, encoding: .utf8)) ?? ""
            let currentEditor = (try? String(contentsOf: editorFile, encoding: .utf8)) ?? ""
            return currentProcessor != initialProcessor || currentEditor != initialEditor
        }

        if !genResult.success && !filesWereModified() {
            // Claude failed AND didn't modify files — retry with a more direct prompt
            log("Generation incomplete — retrying with direct instructions...")
            setStep(.generatingDSP)

            let retryPrompt = """
            The source files have a starter implementation but you need to customize them
            for this specific plugin: \(config.prompt)
            Type: \(pluginRole)

            The starter code has basic gain/mix parameters. You must REPLACE them with
            parameters appropriate for this plugin. Read CLAUDE.md for the full guide.

            1. Read CLAUDE.md (expert reference)
            2. Read all Source/ files
            3. Replace createParameterLayout() with parameters specific to: \(config.prompt)
            4. Replace processBlock() with DSP logic matching the plugin concept
            5. Update the editor: new sliders/controls for each new parameter
            6. Update resized() layout

            Start by reading CLAUDE.md now.
            """

            let _ = await ClaudeCodeService.run(
                prompt: retryPrompt,
                projectDir: project.directory,
                timeoutSeconds: 300,
                onEvent: { [weak self] event in
                    Task { @MainActor in
                        self?.handleClaudeEvent(event)
                    }
                }
            )
            // Whether retry succeeds or not, proceed — stubs already pass validation
        }

        try Task.checkCancellation()

        try await ensureUIStepIsVisible(
            projectDir: project.directory,
            initialSnapshot: initialEditorSnapshot
        )

        setStep(.compiling)
        try await BuildLoop.run(projectDir: project.directory, callbacks: callbacks)

        try Task.checkCancellation()

        do {
            try await GenerationQualityEnforcer.enforce(
                projectDir: project.directory,
                pluginType: project.pluginType,
                interfaceStyle: project.interfaceStyle.rawValue,
                userIntent: config.prompt,
                callbacks: callbacks
            )
        } catch {
            throw GenerationError.generationFailed(error.localizedDescription)
        }

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

        let plugin = Plugin(
            id: UUID(),
            name: project.pluginName,
            type: project.pluginType,
            prompt: config.prompt,
            createdAt: Date(),
            formats: formats,
            installPaths: installPaths,
            iconColor: iconColor,
            status: .installed,
            buildDirectory: project.directory.path
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
        let initialEditorSnapshot = captureEditorSnapshot(in: projectDir)

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
            timeoutSeconds: 300,
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

        try await ensureUIStepIsVisible(
            projectDir: projectDir,
            initialSnapshot: initialEditorSnapshot
        )

        setStep(.compiling)
        try await BuildLoop.run(projectDir: projectDir, callbacks: callbacks)

        try Task.checkCancellation()

        do {
            try await GenerationQualityEnforcer.enforce(
                projectDir: projectDir,
                pluginType: config.plugin.type,
                interfaceStyle: "Refine existing plugin",
                userIntent: config.modification,
                callbacks: callbacks
            )
        } catch {
            throw GenerationError.generationFailed(error.localizedDescription)
        }

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

        // Return updated plugin, preserving identity
        var updated = config.plugin
        updated.installPaths = installPaths
        updated.prompt = config.plugin.prompt + "\n-> " + config.modification
        updated.status = .installed

        return updated
    }

    // MARK: - Helpers

    private func setStep(_ step: GenerationStep) {
        let prev = currentStep
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = step
        }
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
        switch event {
        case .toolUse(let tool, let filePath):
            let normalizedTool = tool.lowercased()
            if let path = filePath {
                let filename = URL(fileURLWithPath: path).lastPathComponent
                if normalizedTool.contains("write") || normalizedTool.contains("edit") || normalizedTool.contains("file_activity") {
                    log("WRITE: \(filename)", style: .normal)
                    if path.contains("Processor") {
                        setStep(.generatingDSP)
                    } else if path.contains("Editor") || path.contains("LookAndFeel") {
                        setStep(.generatingUI)
                    }
                } else if normalizedTool.contains("read") {
                    log("READ: \(filename)", style: .normal)
                }
            }
        case .text(let t):
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.count < 120 {
                log(trimmed, style: .normal)
            }
        default:
            break
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

    private func captureEditorSnapshot(in projectDir: URL) -> EditorSnapshot {
        let editorH = projectDir.appendingPathComponent("Source/PluginEditor.h")
        let editorCPP = projectDir.appendingPathComponent("Source/PluginEditor.cpp")
        let lookAndFeel = projectDir.appendingPathComponent("Source/FoundryLookAndFeel.h")

        return EditorSnapshot(
            header: (try? String(contentsOf: editorH, encoding: .utf8)) ?? "",
            implementation: (try? String(contentsOf: editorCPP, encoding: .utf8)) ?? "",
            lookAndFeel: (try? String(contentsOf: lookAndFeel, encoding: .utf8)) ?? ""
        )
    }

    private func ensureUIStepIsVisible(
        projectDir: URL,
        initialSnapshot: EditorSnapshot
    ) async throws {
        let currentSnapshot = captureEditorSnapshot(in: projectDir)
        guard currentSnapshot != initialSnapshot else { return }
        guard currentStep != .generatingUI else { return }

        setStep(.generatingUI)
        try await Task.sleep(for: .milliseconds(450))
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

private struct EditorSnapshot: Equatable {
    let header: String
    let implementation: String
    let lookAndFeel: String
}
