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

        let initialEditorSnapshot = captureEditorSnapshot(in: project.directory)

        // Step 2: Generate code with Claude
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

        if isAIInfrastructureFailure(genResult.error) {
            throw GenerationError.generationFailed(genResult.error ?? "Claude Code CLI is unavailable")
        }

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

        try await ensureUIStepIsVisible(
            projectDir: project.directory,
            initialSnapshot: initialEditorSnapshot
        )

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

        do {
            try await enforceGenerationQuality(
                projectDir: project.directory,
                pluginType: project.pluginType,
                interfaceStyle: project.interfaceStyle.rawValue,
                userIntent: config.prompt
            )
        } catch {
            throw GenerationError.generationFailed(error.localizedDescription)
        }

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
            throw GenerationError.assemblyFailed("No build directory found — cannot refine this plugin")
        }

        let projectDir = URL(fileURLWithPath: buildDir)

        guard FileManager.default.fileExists(atPath: buildDir) else {
            throw GenerationError.assemblyFailed("Build directory no longer exists: \(buildDir)")
        }

        let initialEditorSnapshot = captureEditorSnapshot(in: projectDir)

        // Step 1: Run Claude with the modification prompt
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

        do {
            try await enforceGenerationQuality(
                projectDir: projectDir,
                pluginType: config.plugin.type,
                interfaceStyle: "Refine existing plugin",
                userIntent: config.modification
            )
        } catch {
            throw GenerationError.generationFailed(error.localizedDescription)
        }

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

    private func enforceGenerationQuality(
        projectDir: URL,
        pluginType: PluginType,
        interfaceStyle: String,
        userIntent: String
    ) async throws {
        do {
            try GeneratedPluginValidator.validate(projectDir: projectDir, pluginType: pluginType)
            return
        } catch let validationError as GeneratedPluginValidator.ValidationError {
            var latestValidationError = validationError

            for recoveryAttempt in 1...2 {
                setStep(.generatingDSP)

                let rewritePrompt = """
                The plugin compiled, but it is still too close to the starter template.
                You must perform a stronger rewrite before this plugin can be accepted.

                User intent:
                \(userIntent)

                Current inferred archetype: \(pluginType.displayName)
                Current interface direction: \(interfaceStyle)

                Validation issues:
                \(latestValidationError.localizedDescription)

                Required fixes:
                - Remove every line containing \(ProjectAssembler.templateMarker)
                - Replace the starter parameter set with a purpose-built set for this plugin
                - Make material changes to BOTH DSP/processing code and editor layout
                - Ensure every parameter has a matching visible control
                - Keep class names unchanged
                - Do not modify CMakeLists.txt

                Read Source/PluginProcessor.h/.cpp and Source/PluginEditor.h/.cpp again before editing.
                Do not explain the plan. Use your tools and rewrite the code now.
                """

                let rewriteResult = await ClaudeCodeService.run(
                    prompt: rewritePrompt,
                    projectDir: projectDir,
                    timeoutSeconds: 240,
                    onEvent: { [weak self] event in
                        Task { @MainActor in
                            self?.handleClaudeEvent(event)
                        }
                    }
                )

                if !rewriteResult.success {
                    let processorPath = projectDir.appendingPathComponent("Source/PluginProcessor.cpp")
                    let editorPath = projectDir.appendingPathComponent("Source/PluginEditor.cpp")
                    let processor = (try? String(contentsOf: processorPath, encoding: .utf8)) ?? ""
                    let editor = (try? String(contentsOf: editorPath, encoding: .utf8)) ?? ""
                    if processor.isEmpty || editor.isEmpty {
                        throw validationError
                    }
                }

                setStep(.compiling)
                var buildResult = try await BuildRunner.build(projectDir: projectDir, skipConfigure: true)

                if !buildResult.success {
                    setStep(.generatingDSP)
                    let _ = await ClaudeCodeService.fix(
                        errors: buildResult.errors,
                        projectDir: projectDir,
                        attempt: recoveryAttempt,
                        onEvent: { [weak self] event in
                            Task { @MainActor in
                                self?.handleClaudeEvent(event)
                            }
                        }
                    )
                    setStep(.compiling)
                    buildResult = try await BuildRunner.build(projectDir: projectDir, skipConfigure: true)
                }

                guard buildResult.success else {
                    throw GenerationError.buildFailed(buildResult.errors)
                }

                guard await BuildRunner.smokeTest(projectDir: projectDir) else {
                    throw GenerationError.buildFailed("Build succeeded but smoke test failed after quality rewrite.")
                }

                do {
                    try GeneratedPluginValidator.validate(projectDir: projectDir, pluginType: pluginType)
                    return
                } catch let nextValidationError as GeneratedPluginValidator.ValidationError {
                    latestValidationError = nextValidationError
                }
            }

            throw latestValidationError
        }
    }
}

private struct EditorSnapshot: Equatable {
    let header: String
    let implementation: String
    let lookAndFeel: String
}

private enum GeneratedPluginValidator {

    enum ValidationError: LocalizedError {
        case unchangedTemplate([String])

        var errorDescription: String? {
            switch self {
            case .unchangedTemplate(let issues):
                return """
                Generation finished, but the plugin is still too close to the base template:
                \(issues.map { "- \($0)" }.joined(separator: "\n"))
                """
            }
        }
    }

    static func validate(projectDir: URL, pluginType: PluginType) throws {
        let sourceDir = projectDir.appendingPathComponent("Source")
        let processorPath = sourceDir.appendingPathComponent("PluginProcessor.cpp")
        let editorPath = sourceDir.appendingPathComponent("PluginEditor.cpp")

        let processor = try String(contentsOf: processorPath, encoding: .utf8)
        let editor = try String(contentsOf: editorPath, encoding: .utf8)

        var issues: [String] = []

        if processor.contains(ProjectAssembler.templateMarker) || editor.contains(ProjectAssembler.templateMarker) {
            issues.append("the generator left template placeholder markers in the source files")
        }

        let parameterIDs = extractMatches(
            pattern: #"ParameterID\{\"([^\"]+)\""#,
            in: processor
        )

        for parameterID in parameterIDs where !editor.contains("\"\(parameterID)\"") {
            issues.append("parameter `\(parameterID)` does not appear to have a matching editor control")
        }

        let baselineParameters: Set<String> = switch pluginType {
        case .instrument:
            ["attack", "decay", "sustain", "release", "gain"]
        case .effect:
            ["gain", "mix"]
        case .utility:
            ["inputGain", "width", "outputGain"]
        }

        if Set(parameterIDs) == baselineParameters {
            issues.append("the parameter set still matches the starter template for this plugin archetype")
        }

        guard issues.isEmpty else {
            throw ValidationError.unchangedTemplate(issues)
        }
    }

    private static func extractMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let resultRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[resultRange])
        }
    }
}
