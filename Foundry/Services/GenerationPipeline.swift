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

        let genPrompt = "Generate a complete \(project.isSynth ? "synthesizer" : "audio effect") plugin: \(config.prompt)"
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

        // Check if Claude actually generated code, regardless of exit code.
        // Claude may exit non-zero due to timeout/max-turns but still have produced valid code.
        let processorFile = project.directory.appendingPathComponent("Source/PluginProcessor.cpp")
        let processorData = try? Data(contentsOf: processorFile)
        let processorModified = (processorData?.count ?? 0) > 500 // Template is ~1KB, real code is much more

        if !genResult.success && !processorModified {
            throw GenerationError.generationFailed(genResult.error ?? "Unknown error")
        }

        try Task.checkCancellation()

        // Step 3: Build (with retry loop)
        setStep(.compiling)

        var lastErrors = ""
        var buildSucceeded = false

        for attempt in 1...3 {
            buildAttempt = attempt

            let buildResult = try await BuildRunner.build(projectDir: project.directory)

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
            status: .installed
        )

        // Cleanup temp dir (fire and forget)
        Task.detached {
            try? FileManager.default.removeItem(at: project.directory)
        }

        return plugin
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
