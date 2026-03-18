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
                Read CLAUDE.md first, then fix the source files using your tools. Act immediately.

                The plugin compiled but validation found implementation gaps that must be fixed.

                User intent: \(userIntent)
                Plugin type: \(pluginType.displayName)
                Interface direction: \(interfaceStyle)

                Issues found:
                \(latestValidationError.localizedDescription)

                Fix these issues:
                - Implement parameters in createParameterLayout() appropriate for this plugin
                - Write real DSP processing logic in processBlock()
                - Ensure every parameter has a matching visible UI control
                - Keep class names unchanged, do not modify CMakeLists.txt

                Read the source files, then fix using your Edit/Write tools.
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
        case insufficientImplementation([String])

        var errorDescription: String? {
            switch self {
            case .insufficientImplementation(let issues):
                return """
                Generation finished but the plugin implementation is incomplete:
                \(issues.map { "- \($0)" }.joined(separator: "\n"))
                """
            }
        }
    }

    static func validate(projectDir: URL, pluginType: PluginType) throws {
        let sourceDir = projectDir.appendingPathComponent("Source")
        let processorCPP = try String(contentsOf: sourceDir.appendingPathComponent("PluginProcessor.cpp"), encoding: .utf8)
        let editorCPP = try String(contentsOf: sourceDir.appendingPathComponent("PluginEditor.cpp"), encoding: .utf8)

        var issues: [String] = []

        // 1. Parameters exist
        let parameterIDs = extractMatches(pattern: #"ParameterID\{"([^"]+)""#, in: processorCPP)
        if parameterIDs.isEmpty {
            issues.append("no parameters defined in createParameterLayout()")
        }

        // 2. processBlock has real DSP
        if let body = extractFunctionBody(named: "processBlock", in: processorCPP), body.count < 200 {
            issues.append("processBlock() appears to have no meaningful DSP implementation")
        }

        // 3. Every parameter has a UI control
        for paramID in parameterIDs where !editorCPP.contains("\"\(paramID)\"") {
            issues.append("parameter `\(paramID)` has no matching UI control in the editor")
        }

        // 4. Editor has visible controls
        let visibleCount = editorCPP.components(separatedBy: "addAndMakeVisible").count - 1
        if visibleCount < 2 {
            issues.append("editor has fewer than 2 visible controls — the UI is essentially empty")
        }

        // 5. Instruments need voice rendering
        if pluginType == .instrument {
            let processorH = (try? String(contentsOf: sourceDir.appendingPathComponent("PluginProcessor.h"), encoding: .utf8)) ?? ""
            if !processorH.contains("renderNextBlock") && !processorCPP.contains("renderNextBlock") {
                issues.append("instrument plugin has no voice rendering implementation")
            }
        }

        guard issues.isEmpty else {
            throw ValidationError.insufficientImplementation(issues)
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

    private static func extractFunctionBody(named name: String, in source: String) -> String? {
        guard let startRange = source.range(of: "::\(name)(") else { return nil }
        var braceCount = 0
        var bodyStart: String.Index?
        var index = startRange.upperBound

        while index < source.endIndex {
            let ch = source[index]
            if ch == "{" {
                braceCount += 1
                if bodyStart == nil { bodyStart = index }
            } else if ch == "}" {
                braceCount -= 1
                if braceCount == 0, let start = bodyStart {
                    return String(source[start...index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
