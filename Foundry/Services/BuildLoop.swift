import Foundation

struct PipelineCallbacks: Sendable {
    let onBuildAttempt: @MainActor @Sendable (Int) -> Void
    let onStepChange: @MainActor @Sendable (GenerationStep) -> Void
    let onClaudeEvent: @MainActor @Sendable (ClaudeCodeService.ClaudeEvent) -> Void
}

enum BuildLoop {

    struct Dependencies: Sendable {
        let build: @Sendable (URL, Bool) async throws -> BuildRunner.BuildResult
        let smokeTest: @Sendable (URL) async -> Bool
        let fix: @Sendable (String, URL, Int, PipelineCallbacks) async -> Void

        static let live = Dependencies(
            build: { projectDir, skipConfigure in
                try await BuildRunner.build(projectDir: projectDir, skipConfigure: skipConfigure)
            },
            smokeTest: { projectDir in
                await BuildRunner.smokeTest(projectDir: projectDir)
            },
            fix: { errors, projectDir, attempt, callbacks in
                let _ = await ClaudeCodeService.fix(
                    errors: errors,
                    projectDir: projectDir,
                    attempt: attempt,
                    onEvent: { event in
                        Task { @MainActor in
                            callbacks.onClaudeEvent(event)
                        }
                    }
                )
            }
        )
    }

    /// Build loop with no artificial attempt limit.
    /// Exits on success or task cancellation — the compiler is the only judge.
    static func run(
        projectDir: URL,
        callbacks: PipelineCallbacks,
        dependencies: Dependencies = .live
    ) async throws {
        var lastErrors = ""
        var attempt = 0

        while true {
            try Task.checkCancellation()

            attempt += 1
            await callbacks.onBuildAttempt(attempt)

            let buildResult = try await dependencies.build(projectDir, attempt > 1)

            if buildResult.success {
                let smokeOK = await dependencies.smokeTest(projectDir)
                if smokeOK {
                    return // success — done
                }

                // Smoke test failed — fix and retry
                lastErrors = "Build succeeded but smoke test failed: plugin bundles are missing or invalid in the build output."
                await callbacks.onStepChange(.generatingDSP)
                await dependencies.fix(lastErrors, projectDir, attempt, callbacks)
                await callbacks.onStepChange(.compiling)
                continue
            }

            lastErrors = buildResult.errors

            // Build failed — fix and retry
            await callbacks.onStepChange(.generatingDSP)
            await dependencies.fix(buildResult.errors, projectDir, attempt, callbacks)
            await callbacks.onStepChange(.compiling)
        }
    }
}
