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
                The plugin compiled but FAILED automated validation. You must fix it NOW.

                User intent: \(userIntent)
                Plugin type: \(pluginType.displayName)
                Interface direction: \(interfaceStyle)

                ## VALIDATION FAILURES:
                \(latestValidationError.localizedDescription)

                ## Step-by-step — follow this order:
                1. Read CLAUDE.md for JUCE patterns
                2. Read Source/PluginProcessor.cpp and Source/PluginEditor.cpp
                3. Fix each issue:

                **If "no parameters defined":**
                Edit createParameterLayout() in PluginProcessor.cpp — add params like:
                ```cpp
                params.push_back(std::make_unique<juce::AudioParameterFloat>(
                    juce::ParameterID{"drive", 1}, "Drive",
                    juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.5f));
                ```

                **If "no meaningful DSP":**
                Edit processBlock() — read parameters with getRawParameterValue(), process samples in a per-channel/per-sample loop with real math (tanh, filters, delays).

                **If "no matching UI control":**
                For each parameter, add in PluginEditor.h: Slider + Label + SliderAttachment members.
                In constructor: set slider style, addAndMakeVisible(), create attachment.
                In resized(): setBounds() for all controls.

                **If "fewer than 2 visible controls":**
                Every parameter needs a slider with addAndMakeVisible(). Add labels too.

                **If "instrument needs enough controls":**
                Think about what the user asked for and add parameters that let them shape and
                explore the sound. Read the synthesis knowledge reference in CLAUDE.md for ideas.

                **If "unmodified starter code":**
                The voice still uses the basic sine stub. You MUST redesign it from scratch.
                Read CLAUDE.md for synthesis building blocks, then design your own instrument
                engine that matches what the user asked for. Replace the renderNextBlock body,
                add new member variables, and create parameters for every control you add.

                Keep class names unchanged. Do NOT modify CMakeLists.txt.
                Use Edit to modify existing methods — do NOT add duplicate definitions.
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

        // 1. Parameters exist — match multiple syntaxes:
        //    ParameterID{"x", 1}  or  ParameterID{ "x", 1 }  or  ParameterID ("x", 1)
        //    Also detect AudioParameterFloat/Choice/Bool/Int constructors as evidence
        var parameterIDs = extractMatches(pattern: #"ParameterID\s*[\{(]\s*"([^"]+)""#, in: processorCPP)
        if parameterIDs.isEmpty {
            // Fallback: look for AudioParameter* constructors with string IDs
            parameterIDs = extractMatches(pattern: #"AudioParameter(?:Float|Choice|Bool|Int)\s*\([^"]*"([^"]+)""#, in: processorCPP)
        }
        if parameterIDs.isEmpty {
            issues.append("no parameters defined in createParameterLayout()")
        }

        // 2. processBlock has real DSP — check for meaningful processing patterns,
        //    not just body size. The stub is ~150 chars of boilerplate, so size alone
        //    is unreliable. Instead, look for evidence of actual audio work.
        if let body = extractFunctionBody(named: "processBlock", in: processorCPP) {
            let dspIndicators = [
                "getRawParameterValue",   // reading parameters
                "getWritePointer",        // writing audio samples
                "getNextValue",           // SmoothedValue
                "std::tanh", "std::sin", "std::cos", "std::abs", "std::clamp", "std::fmod",  // math
                "dsp::",                  // JUCE DSP module usage
                "delayLine", "DelayLine", // delay processing
                "filter", "Filter",       // filter processing
                ".process(",              // juce::dsp process calls
                "processSample",          // custom sample processing
            ]
            let hasDSP = dspIndicators.contains { body.localizedCaseInsensitiveContains($0) }
            // Also accept body size > 400 as sufficient (real implementations are much larger than stubs)
            if !hasDSP && body.count < 400 {
                issues.append("processBlock() appears to have no meaningful DSP implementation")
            }
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

        // 5. Instruments need voice rendering + sufficient sound design controls
        if pluginType == .instrument {
            let processorH = (try? String(contentsOf: sourceDir.appendingPathComponent("PluginProcessor.h"), encoding: .utf8)) ?? ""
            if !processorH.contains("renderNextBlock") && !processorCPP.contains("renderNextBlock") {
                issues.append("instrument plugin has no voice rendering implementation")
            }

            // A playable instrument needs enough parameters to shape the sound
            if parameterIDs.count < 5 {
                issues.append("instrument plugin has only \(parameterIDs.count) parameters — a playable instrument needs enough controls for the user to shape and explore the sound")
            }

            // Check that the voice has been substantially modified from the stub.
            // The stub sine pattern is a known fingerprint. If it's still there AND the voice
            // code hasn't grown significantly, the voice wasn't redesigned.
            let stubSineFingerprint = "std::sin(phase * juce::MathConstants<double>::twoPi)"
            let hasStubSine = processorH.contains(stubSineFingerprint)

            // Count non-empty lines in the voice section as a proxy for implementation size.
            // The stub voice is ~35 lines. A real implementation should be significantly larger.
            if let voiceStart = processorH.range(of: "class \(processorH.contains("Voice") ? "" : "")"),
               hasStubSine {
                // If the stub sine is still there, check if substantial code was added around it
                let voiceLines = processorH.components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .count
                // The full stub header (voice + processor) is ~65 non-empty lines.
                // If Claude added real synthesis, it should be 90+ lines.
                if voiceLines < 90 {
                    issues.append("instrument voice appears to be the unmodified starter code — it must be redesigned as a complete instrument matching the user's request")
                }
            } else if hasStubSine && parameterIDs.count <= 3 {
                // Stub sine + only starter params = nothing was changed
                issues.append("instrument voice appears to be the unmodified starter code — it must be redesigned as a complete instrument matching the user's request")
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
