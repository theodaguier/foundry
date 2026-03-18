import Foundation

enum GenerationQualityEnforcer {

    static func enforce(
        projectDir: URL,
        pluginType: PluginType,
        interfaceStyle: String,
        userIntent: String,
        callbacks: PipelineCallbacks
    ) async throws {
        do {
            try GeneratedPluginValidator.validate(projectDir: projectDir, pluginType: pluginType)
            return
        } catch let validationError as GeneratedPluginValidator.ValidationError {
            var latestValidationError = validationError

            for recoveryAttempt in 1...2 {
                await callbacks.onStepChange(.generatingDSP)

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
                    onEvent: { event in
                        Task { @MainActor in
                            callbacks.onClaudeEvent(event)
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

                await callbacks.onStepChange(.compiling)
                var buildResult = try await BuildRunner.build(projectDir: projectDir, skipConfigure: true)

                if !buildResult.success {
                    await callbacks.onStepChange(.generatingDSP)
                    let _ = await ClaudeCodeService.fix(
                        errors: buildResult.errors,
                        projectDir: projectDir,
                        attempt: recoveryAttempt,
                        onEvent: { event in
                            Task { @MainActor in
                                callbacks.onClaudeEvent(event)
                            }
                        }
                    )
                    await callbacks.onStepChange(.compiling)
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
