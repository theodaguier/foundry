import XCTest
@testable import Foundry

final class ClaudeCodeServiceTests: XCTestCase {

    func testBuildArgumentsContainsMaxTurns50() {
        let args = ClaudeCodeService.buildArguments(prompt: "test")
        guard let maxTurnsIndex = args.firstIndex(of: "--max-turns") else {
            return XCTFail("--max-turns flag is missing from arguments")
        }
        XCTAssertEqual(args[maxTurnsIndex + 1], "50", "max-turns should be 50")
    }

    func testBuildArgumentsContainsAppendSystemPrompt() {
        let args = ClaudeCodeService.buildArguments(prompt: "test")
        guard let idx = args.firstIndex(of: "--append-system-prompt") else {
            return XCTFail("--append-system-prompt flag is missing from arguments")
        }
        let systemPrompt = args[idx + 1]
        XCTAssertTrue(systemPrompt.contains("MUST use tools"), "system prompt should force tool usage")
        XCTAssertTrue(systemPrompt.contains("Never respond with only text"), "system prompt should discourage text-only responses")
    }

    func testBuildArgumentsDoesNotContainAllowedTools() {
        let args = ClaudeCodeService.buildArguments(prompt: "test")
        XCTAssertFalse(args.contains("--allowedTools"), "--allowedTools does not actually force tool usage and should not be used")
    }

    func testBuildArgumentsContainsRequiredFlags() {
        let args = ClaudeCodeService.buildArguments(prompt: "hello")
        XCTAssertTrue(args.contains("-p"))
        XCTAssertTrue(args.contains("hello"))
        XCTAssertTrue(args.contains("--dangerously-skip-permissions"))
        XCTAssertTrue(args.contains("stream-json"))
        XCTAssertTrue(args.contains("--verbose"))
    }

    func testBuildArgumentsUsesSonnetModel() {
        let args = ClaudeCodeService.buildArguments(prompt: "test")
        guard let idx = args.firstIndex(of: "--model") else {
            return XCTFail("--model flag is missing from arguments")
        }
        XCTAssertEqual(args[idx + 1], "sonnet", "should use sonnet for faster generation")
    }
}
