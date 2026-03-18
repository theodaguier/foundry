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

@Observable @MainActor
final class GenerationPipeline {

    var currentStep: GenerationStep = .preparingProject
    var isRunning = false
    var buildAttempt = 0
    private var task: Task<Void, Never>?

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
        You are modifying a working JUCE \(pluginRole) plugin. You MUST use your tools to read and edit files.

        Generation target:
        - Inferred archetype: \(project.pluginType.displayName)
        - Inferred interface style: \(project.interfaceStyle.rawValue)

        START by reading these files (use your Read tool):
        1. CLAUDE.md
        2. Source/PluginProcessor.h
        3. Source/PluginProcessor.cpp
        4. Source/PluginEditor.h
        5. Source/PluginEditor.cpp

        THEN use your Edit/Write tools to modify the code to create: \(config.prompt)

        Specifically, you MUST edit:
        - PluginProcessor.h/cpp: add parameters and implement DSP or utility behavior for this specific \(pluginRole)
        - PluginEditor.h/cpp: create an intentional interface with grouped sections and appropriate controls for every parameter
        - FoundryLookAndFeel.h: change accentColour to match the plugin character\(presetInstruction)
        - Remove EVERY line containing \(ProjectAssembler.templateMarker)

        Do NOT just describe what to do - actually edit the files using your tools.
        Keep class names unchanged. The plugin must compile with C++17 and JUCE.
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

        // Templates are complete and functional - even if Claude fails to modify them,
        // the plugin will compile and work with basic controls.
        // Only bail out if Claude explicitly errored and returned nothing.
        if !genResult.success {
            let processorFile = project.directory.appendingPathComponent("Source/PluginProcessor.cpp")
            let processorContent = (try? String(contentsOf: processorFile, encoding: .utf8)) ?? ""
            let editorFile = project.directory.appendingPathComponent("Source/PluginEditor.cpp")
            let editorContent = (try? String(contentsOf: editorFile, encoding: .utf8)) ?? ""

            if processorContent.isEmpty || editorContent.isEmpty {
                throw GenerationError.generationFailed(genResult.error ?? "Claude did not generate any code")
            }
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

        // Keep temp dir for debugging - can inspect what Claude generated
        // TODO: re-enable cleanup once generation is stable
        // Task.detached {
        //     try? FileManager.default.removeItem(at: project.directory)
        // }

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
        You are modifying an existing JUCE \(pluginRole) plugin. You MUST use your tools to read and edit files.

        START by reading these files (use your Read tool):
        1. CLAUDE.md
        2. Source/PluginProcessor.h
        3. Source/PluginProcessor.cpp
        4. Source/PluginEditor.h
        5. Source/PluginEditor.cpp

        The user wants this modification: \(config.modification)

        Use your Edit tool to make targeted changes. Keep everything else working.
        Remove any remaining \(ProjectAssembler.templateMarker) markers if they still exist.
        Do NOT rewrite files from scratch - only change what's needed.
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
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = step
        }
    }

    private func handleClaudeEvent(_ event: ClaudeCodeService.ClaudeEvent) {
        switch event {
        case .toolUse(let tool, let filePath):
            let normalizedTool = tool.lowercased()
            guard normalizedTool.contains("write")
                    || normalizedTool.contains("edit")
                    || normalizedTool.contains("file_activity") else { return }
            if let path = filePath {
                if path.contains("Processor") {
                    setStep(.generatingDSP)
                } else if path.contains("Editor") || path.contains("LookAndFeel") {
                    setStep(.generatingUI)
                }
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
