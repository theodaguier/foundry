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

    // MARK: - Pipeline

    private func execute(config: GenerationConfig) async throws -> Plugin {
        // Step 1: Assemble project
        setStep(.preparingProject)

        let project: ProjectAssembler.AssembledProject
        do {
            project = try ProjectAssembler.assemble(config: config)
        } catch {
            throw GenerationError.assemblyFailed(error.localizedDescription)
        }

        try Task.checkCancellation()

        // Step 2: Generate code with Claude
        setStep(.generatingDSP)

        let pluginType = project.isSynth ? "synthesizer" : "audio effect"
        let presetCount = config.presetCount.rawValue
        let presetInstruction = presetCount > 0
            ? "\n- Implement exactly \(presetCount) presets with a ComboBox selector in the UI (see CLAUDE.md Presets section)"
            : ""
        let genPrompt = """
        You are modifying a working JUCE \(pluginType) plugin. You MUST use your tools to read and edit files.

        START by reading these files (use your Read tool):
        1. CLAUDE.md
        2. Source/PluginProcessor.h
        3. Source/PluginProcessor.cpp
        4. Source/PluginEditor.h
        5. Source/PluginEditor.cpp

        THEN use your Edit/Write tools to modify the code to create: \(config.prompt)

        Specifically, you MUST edit:
        - PluginProcessor.h/cpp: add parameters and implement DSP for this specific \(pluginType)
        - PluginEditor.h/cpp: add a Slider + Label + SliderAttachment for EVERY new parameter, update layout in resized()
        - FoundryLookAndFeel.h: change accentColour to match the plugin character\(presetInstruction)

        Do NOT just describe what to do — actually edit the files using your tools.
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

        // Templates are complete and functional — even if Claude fails to modify them,
        // the plugin will compile and work with basic controls.
        // Only bail out if Claude explicitly errored and returned nothing.
        if !genResult.success {
            // Check if Claude at least modified something
            let processorFile = project.directory.appendingPathComponent("Source/PluginProcessor.cpp")
            let processorContent = (try? String(contentsOf: processorFile, encoding: .utf8)) ?? ""
            let editorFile = project.directory.appendingPathComponent("Source/PluginEditor.cpp")
            let editorContent = (try? String(contentsOf: editorFile, encoding: .utf8)) ?? ""

            // If files still exist and have content, proceed to build —
            // the working template will produce a functional plugin regardless.
            if processorContent.isEmpty || editorContent.isEmpty {
                throw GenerationError.generationFailed(genResult.error ?? "Claude did not generate any code")
            }
        }

        try Task.checkCancellation()

        // Step 3: Build (with retry loop)
        setStep(.compiling)

        var lastErrors = ""
        var buildSucceeded = false

        for attempt in 1...3 {
            buildAttempt = attempt

            let buildResult = try await BuildRunner.build(
                projectDir: project.directory,
                skipConfigure: attempt > 1
            )

            if buildResult.success {
                // Smoke test: check bundles exist
                let smokeOK = await BuildRunner.smokeTest(projectDir: project.directory)
                if smokeOK {
                    buildSucceeded = true
                    break
                }

                // Smoke test failed — only retry if we have attempts left
                if attempt < 3 {
                    lastErrors = "Build succeeded but smoke test failed: plugin bundles are missing or invalid in the build output."
                    setStep(.generatingDSP)
                    let _ = await ClaudeCodeService.fix(
                        errors: lastErrors,
                        projectDir: project.directory,
                        attempt: attempt,
                        onEvent: { [weak self] event in
                            Task { @MainActor in
                                self?.handleClaudeEvent(event)
                            }
                        }
                    )
                    setStep(.compiling)
                    continue
                } else {
                    // Smoke test failed on last attempt — still try to install if bundles exist
                    buildSucceeded = true
                    break
                }
            }

            lastErrors = buildResult.errors

            // Build failed — send errors to Claude for fixing
            if attempt < 3 {
                setStep(.generatingDSP)
                // Don't fail the whole pipeline if Claude's fix attempt exits non-zero
                // (it may still have written valid fixes)
                let _ = await ClaudeCodeService.fix(
                    errors: buildResult.errors,
                    projectDir: project.directory,
                    attempt: attempt,
                    onEvent: { [weak self] event in
                        Task { @MainActor in
                            self?.handleClaudeEvent(event)
                        }
                    }
                )
                setStep(.compiling)
            } else {
                throw GenerationError.buildFailed(lastErrors)
            }
        }

        guard buildSucceeded else {
            throw GenerationError.buildFailed(lastErrors)
        }

        try Task.checkCancellation()

        // Step 5: Install
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

        // Generate a muted accent color
        let colors = ["#C8C4BC", "#A8B4A0", "#B0A898", "#9CAAB8", "#B8A8B0", "#A0A8B0"]
        let iconColor = colors.randomElement()!

        let plugin = Plugin(
            id: UUID(),
            name: project.pluginName,
            type: project.isSynth ? .synth : .effect,
            prompt: config.prompt,
            createdAt: Date(),
            formats: formats,
            installPaths: installPaths,
            iconColor: iconColor,
            status: .installed,
            buildDirectory: project.directory.path
        )

        // Keep temp dir for debugging — can inspect what Claude generated
        // TODO: re-enable cleanup once generation is stable
        // Task.detached {
        //     try? FileManager.default.removeItem(at: project.directory)
        // }

        return plugin
    }

    // MARK: - Refine Pipeline

    private func executeRefine(config: RefineConfig) async throws -> Plugin {
        guard let buildDir = config.plugin.buildDirectory else {
            throw GenerationError.assemblyFailed("No build directory found — cannot refine this plugin")
        }

        let projectDir = URL(fileURLWithPath: buildDir)

        guard FileManager.default.fileExists(atPath: buildDir) else {
            throw GenerationError.assemblyFailed("Build directory no longer exists: \(buildDir)")
        }

        // Step 1: Run Claude with the modification prompt
        setStep(.generatingDSP)

        let pluginType = config.plugin.type == .synth ? "synthesizer" : "audio effect"
        let refinePrompt = """
        You are modifying an existing JUCE \(pluginType) plugin. You MUST use your tools to read and edit files.

        START by reading these files (use your Read tool):
        1. CLAUDE.md
        2. Source/PluginProcessor.h
        3. Source/PluginProcessor.cpp
        4. Source/PluginEditor.h
        5. Source/PluginEditor.cpp

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

        if !genResult.success {
            let processorFile = projectDir.appendingPathComponent("Source/PluginProcessor.cpp")
            let processorContent = (try? String(contentsOf: processorFile, encoding: .utf8)) ?? ""
            if processorContent.isEmpty {
                throw GenerationError.generationFailed(genResult.error ?? "Claude did not modify the code")
            }
        }

        try Task.checkCancellation()

        // Step 2: Build (with retry loop)
        setStep(.compiling)

        var lastErrors = ""
        var buildSucceeded = false

        for attempt in 1...3 {
            buildAttempt = attempt

            let buildResult = try await BuildRunner.build(
                projectDir: projectDir,
                skipConfigure: attempt > 1
            )

            if buildResult.success {
                let smokeOK = await BuildRunner.smokeTest(projectDir: projectDir)
                if smokeOK {
                    buildSucceeded = true
                    break
                }

                if attempt < 3 {
                    lastErrors = "Build succeeded but smoke test failed: plugin bundles are missing or invalid."
                    setStep(.generatingDSP)
                    let _ = await ClaudeCodeService.fix(
                        errors: lastErrors,
                        projectDir: projectDir,
                        attempt: attempt,
                        onEvent: { [weak self] event in
                            Task { @MainActor in
                                self?.handleClaudeEvent(event)
                            }
                        }
                    )
                    setStep(.compiling)
                    continue
                } else {
                    buildSucceeded = true
                    break
                }
            }

            lastErrors = buildResult.errors

            if attempt < 3 {
                setStep(.generatingDSP)
                let _ = await ClaudeCodeService.fix(
                    errors: buildResult.errors,
                    projectDir: projectDir,
                    attempt: attempt,
                    onEvent: { [weak self] event in
                        Task { @MainActor in
                            self?.handleClaudeEvent(event)
                        }
                    }
                )
                setStep(.compiling)
            } else {
                throw GenerationError.buildFailed(lastErrors)
            }
        }

        guard buildSucceeded else {
            throw GenerationError.buildFailed(lastErrors)
        }

        try Task.checkCancellation()

        // Step 3: Install
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
        updated.prompt = config.plugin.prompt + "\n→ " + config.modification
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
            guard tool == "Write" || tool == "Edit" else { return }
            if let path = filePath {
                if path.contains("Processor") {
                    setStep(.generatingDSP)
                } else if path.contains("Editor") {
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
}
