import XCTest

/// Verifies prompt contracts for Claude Code CLI invocations.
/// Guards against regressions where Claude spends turns planning
/// instead of editing files (issue #17).
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
            "genPrompt must instruct Claude to read CLAUDE.md first for expert knowledge"
        )
    }

    func testGenPromptMentionsStubs() throws {
        let source = try sourceContents(of: "GenerationPipeline.swift")
        XCTAssertTrue(
            source.contains("minimal stubs"),
            "genPrompt must describe the agent-expert approach (building from stubs)"
        )
    }

    func testRefinePromptReadsSourceFiles() throws {
        let source = try sourceContents(of: "GenerationPipeline.swift")
        XCTAssertTrue(
            source.contains("Read these source files first"),
            "refinePrompt must instruct Claude to read existing source files"
        )
    }

    // MARK: - GenerationQualityEnforcer

    func testRewritePromptReadsClaudeMD() throws {
        let source = try sourceContents(of: "GenerationQualityEnforcer.swift")
        XCTAssertTrue(
            source.contains("Read CLAUDE.md first"),
            "GenerationQualityEnforcer rewritePrompt must reference CLAUDE.md"
        )
    }

    // MARK: - ClaudeCodeService

    func testClaudeCodeServiceUsesMaxTurns50() throws {
        let source = try sourceContents(of: "ClaudeCodeService.swift")
        XCTAssertTrue(source.contains("\"--max-turns\", \"50\""))
        XCTAssertFalse(source.contains("\"--max-turns\", \"30\""))
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

    // MARK: - No template references

    func testNoTemplateMarkerReferences() throws {
        let pipeline = try sourceContents(of: "GenerationPipeline.swift")
        let enforcer = try sourceContents(of: "GenerationQualityEnforcer.swift")
        let assembler = try sourceContents(of: "ProjectAssembler.swift")

        for (name, source) in [("Pipeline", pipeline), ("Enforcer", enforcer), ("Assembler", assembler)] {
            XCTAssertFalse(
                source.contains("FOUNDRY_TEMPLATE_PLACEHOLDER"),
                "\(name) must not reference FOUNDRY_TEMPLATE_PLACEHOLDER — agent-expert approach has no templates"
            )
            XCTAssertFalse(
                source.contains("templateMarker"),
                "\(name) must not reference templateMarker — agent-expert approach has no templates"
            )
        }
    }
}
