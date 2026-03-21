import XCTest

/// Verifies prompt contracts for Claude Code CLI invocations.
/// Guards against regressions in the generation pipeline architecture.
final class PromptContractTests: XCTestCase {

    private func sourceContents(of filename: String) throws -> String {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()            // FoundryTests/
            .deletingLastPathComponent()            // project root
            .appendingPathComponent("Foundry/Services")
        let url = dir.appendingPathComponent(filename)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - GenerationPipeline

    func testGenPromptReadsClaudeMDFirst() throws {
        let source = try sourceContents(of: "GenerationPipeline.swift")
        XCTAssertTrue(
            source.contains("Read CLAUDE.md first"),
            "genPrompt must instruct Claude to read CLAUDE.md first for mission brief"
        )
    }

    func testGenPromptCreatesFromScratch() throws {
        let source = try sourceContents(of: "GenerationPipeline.swift")
        XCTAssertTrue(
            source.contains("from scratch"),
            "genPrompt must tell Claude to create all source files from scratch (no stubs)"
        )
    }

    func testRefinePromptReadsSourceFiles() throws {
        let source = try sourceContents(of: "GenerationPipeline.swift")
        XCTAssertTrue(
            source.contains("Read these source files first"),
            "refinePrompt must instruct Claude to read existing source files"
        )
    }

    func testPipelineHasAuditPass() throws {
        let source = try sourceContents(of: "GenerationPipeline.swift")
        XCTAssertTrue(
            source.contains("Audit pass"),
            "Pipeline must include an audit pass between generation and build"
        )
    }

    func testNoQualityEnforcerReferences() throws {
        let source = try sourceContents(of: "GenerationPipeline.swift")
        XCTAssertFalse(
            source.contains("GenerationQualityEnforcer"),
            "Pipeline must not reference GenerationQualityEnforcer — it has been removed"
        )
    }

    // MARK: - ClaudeCodeService

    func testClaudeCodeServiceUsesMaxTurns25() throws {
        let source = try sourceContents(of: "ClaudeCodeService.swift")
        XCTAssertTrue(source.contains("\"--max-turns\", \"25\""))
    }

    func testClaudeCodeServiceUsesAppendSystemPrompt() throws {
        let source = try sourceContents(of: "ClaudeCodeService.swift")
        XCTAssertTrue(
            source.contains("\"--append-system-prompt\""),
            "ClaudeCodeService must use --append-system-prompt to enforce tool usage"
        )
    }

    func testClaudeCodeServiceUsesSonnetModel() throws {
        let source = try sourceContents(of: "ClaudeCodeService.swift")
        XCTAssertTrue(
            source.contains("\"--model\", \"sonnet\""),
            "ClaudeCodeService must use sonnet for faster generation with less thinking overhead"
        )
    }

    func testClaudeCodeServiceHasAuditMethod() throws {
        let source = try sourceContents(of: "ClaudeCodeService.swift")
        XCTAssertTrue(
            source.contains("static func audit("),
            "ClaudeCodeService must have an audit method for pre-build review"
        )
    }

    func testClaudeCodeServiceUsesWatchdogNotFunctionalTimeout() throws {
        let source = try sourceContents(of: "ClaudeCodeService.swift")
        XCTAssertTrue(
            source.contains("watchdogSeconds = 900"),
            "ClaudeCodeService must use a 15-minute watchdog (900s), not a functional timeout"
        )
    }

    // MARK: - BuildLoop

    func testBuildLoopHasNoMaxAttempts() throws {
        let source = try sourceContents(of: "BuildLoop.swift")
        XCTAssertFalse(
            source.contains("maxAttempts"),
            "BuildLoop must not have a maxAttempts limit — loop exits on success or cancellation"
        )
    }

    // MARK: - No template references

    func testNoTemplateMarkerReferences() throws {
        let pipeline = try sourceContents(of: "GenerationPipeline.swift")
        let assembler = try sourceContents(of: "ProjectAssembler.swift")

        for (name, source) in [("Pipeline", pipeline), ("Assembler", assembler)] {
            XCTAssertFalse(
                source.contains("FOUNDRY_TEMPLATE_PLACEHOLDER"),
                "\(name) must not reference FOUNDRY_TEMPLATE_PLACEHOLDER"
            )
            XCTAssertFalse(
                source.contains("templateMarker"),
                "\(name) must not reference templateMarker"
            )
        }
    }

    // MARK: - ProjectAssembler

    func testProjectAssemblerWritesKnowledgeKit() throws {
        let source = try sourceContents(of: "ProjectAssembler.swift")
        XCTAssertTrue(
            source.contains("writeJuceKit"),
            "ProjectAssembler must write the JUCE knowledge kit"
        )
        XCTAssertFalse(
            source.contains("writeStubFiles"),
            "ProjectAssembler must not write C++ stub files"
        )
    }
}
