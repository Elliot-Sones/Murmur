import XCTest
@testable import Murmur

final class RewritePromptBuilderTests: XCTestCase {
    private let builder = RewritePromptBuilder()

    func testInstructionsDemandOutputOnlyTheRewrittenText() {
        let instructions = builder.instructions()
        XCTAssertTrue(instructions.lowercased().contains("only the rewritten text"))
        XCTAssertTrue(
            instructions.lowercased().contains("preserve"),
            "must instruct preserving meaning unless the instruction says otherwise"
        )
    }

    func testUserPromptContainsSelectionAndInstructionVerbatim() {
        let prompt = builder.userPrompt(
            selection: "we shipped the thing yesterday",
            instruction: "make this more formal"
        )
        XCTAssertTrue(prompt.contains("we shipped the thing yesterday"))
        XCTAssertTrue(prompt.contains("make this more formal"))
    }
}
