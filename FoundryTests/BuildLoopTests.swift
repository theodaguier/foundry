import XCTest
@testable import Foundry

final class BuildLoopTests: XCTestCase {

    @MainActor
    func testRetriesFailedBuildAndSkipsConfigureAfterFirstAttempt() async throws {
        let callbackRecorder = CallbackRecorder()
        let stub = BuildLoopStub(
            buildResults: [
                .init(success: false, output: "", errors: "missing semicolon"),
                .init(success: true, output: "", errors: ""),
            ],
            smokeResults: [true]
        )

        try await BuildLoop.run(
            projectDir: URL(fileURLWithPath: "/tmp/foundry-build-loop-test"),
            callbacks: callbackRecorder.callbacks,
            dependencies: stub.dependencies
        )

        let snapshot = await stub.snapshot()
        XCTAssertEqual(snapshot.buildSkipConfigure, [false, true])
        XCTAssertEqual(snapshot.fixAttempts, [1])
        XCTAssertEqual(snapshot.fixErrors, ["missing semicolon"])
        XCTAssertEqual(callbackRecorder.attempts, [1, 2])
        XCTAssertEqual(callbackRecorder.steps, [.generatingDSP, .compiling])
    }

    @MainActor
    func testRetriesAfterSmokeFailure() async throws {
        let callbackRecorder = CallbackRecorder()
        let stub = BuildLoopStub(
            buildResults: [
                .init(success: true, output: "", errors: ""),
                .init(success: true, output: "", errors: ""),
            ],
            smokeResults: [false, true]
        )

        try await BuildLoop.run(
            projectDir: URL(fileURLWithPath: "/tmp/foundry-build-loop-test"),
            callbacks: callbackRecorder.callbacks,
            dependencies: stub.dependencies
        )

        let snapshot = await stub.snapshot()
        XCTAssertEqual(snapshot.buildSkipConfigure, [false, true])
        XCTAssertEqual(snapshot.fixAttempts, [1])
        XCTAssertEqual(
            snapshot.fixErrors,
            ["Build succeeded but smoke test failed: plugin bundles are missing or invalid in the build output."]
        )
        XCTAssertEqual(callbackRecorder.attempts, [1, 2])
        XCTAssertEqual(callbackRecorder.steps, [.generatingDSP, .compiling])
    }

    @MainActor
    func testThrowsLastBuildErrorAfterMaxAttempts() async throws {
        let callbackRecorder = CallbackRecorder()
        let stub = BuildLoopStub(
            buildResults: [
                .init(success: false, output: "", errors: "first"),
                .init(success: false, output: "", errors: "second"),
                .init(success: false, output: "", errors: "third"),
            ],
            smokeResults: []
        )

        do {
            try await BuildLoop.run(
                projectDir: URL(fileURLWithPath: "/tmp/foundry-build-loop-test"),
                callbacks: callbackRecorder.callbacks,
                dependencies: stub.dependencies
            )
            XCTFail("Expected build loop to throw after the last failed attempt")
        } catch let error as GenerationError {
            guard case .buildFailed(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "third")
        }

        let snapshot = await stub.snapshot()
        XCTAssertEqual(snapshot.buildSkipConfigure, [false, true, true])
        XCTAssertEqual(snapshot.fixAttempts, [1, 2])
        XCTAssertEqual(snapshot.fixErrors, ["first", "second"])
        XCTAssertEqual(callbackRecorder.attempts, [1, 2, 3])
        XCTAssertEqual(
            callbackRecorder.steps,
            [.generatingDSP, .compiling, .generatingDSP, .compiling]
        )
    }
}

@MainActor
private final class CallbackRecorder {
    var attempts: [Int] = []
    var steps: [GenerationStep] = []

    var callbacks: PipelineCallbacks {
        PipelineCallbacks(
            onBuildAttempt: { [weak self] attempt in
                self?.attempts.append(attempt)
            },
            onStepChange: { [weak self] step in
                self?.steps.append(step)
            },
            onClaudeEvent: { _ in }
        )
    }
}

private actor BuildLoopStub {
    private var buildResults: [BuildRunner.BuildResult]
    private var smokeResults: [Bool]
    private var buildSkipConfigure: [Bool] = []
    private var fixAttempts: [Int] = []
    private var fixErrors: [String] = []

    init(buildResults: [BuildRunner.BuildResult], smokeResults: [Bool]) {
        self.buildResults = buildResults
        self.smokeResults = smokeResults
    }

    var dependencies: BuildLoop.Dependencies {
        BuildLoop.Dependencies(
            build: { [self] _, skipConfigure in
                try await nextBuildResult(skipConfigure: skipConfigure)
            },
            smokeTest: { [self] _ in
                await nextSmokeResult()
            },
            fix: { [self] errors, _, attempt, _ in
                await recordFix(errors: errors, attempt: attempt)
            }
        )
    }

    func snapshot() -> Snapshot {
        Snapshot(
            buildSkipConfigure: buildSkipConfigure,
            fixAttempts: fixAttempts,
            fixErrors: fixErrors
        )
    }

    private func nextBuildResult(skipConfigure: Bool) throws -> BuildRunner.BuildResult {
        buildSkipConfigure.append(skipConfigure)
        return buildResults.removeFirst()
    }

    private func nextSmokeResult() -> Bool {
        smokeResults.isEmpty ? false : smokeResults.removeFirst()
    }

    private func recordFix(errors: String, attempt: Int) {
        fixAttempts.append(attempt)
        fixErrors.append(errors)
    }

    struct Snapshot {
        let buildSkipConfigure: [Bool]
        let fixAttempts: [Int]
        let fixErrors: [String]
    }
}
