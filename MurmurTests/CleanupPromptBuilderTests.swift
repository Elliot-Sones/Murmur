import XCTest
@testable import Murmur

final class CleanupPromptBuilderTests: XCTestCase {
    private let builder = CleanupPromptBuilder()

    func testInstructionsContainCoreRules() {
        let instructions = builder.instructions()
        XCTAssertTrue(instructions.contains("filler"), "must instruct filler removal")
        XCTAssertTrue(instructions.contains("punctuation"), "must instruct punctuation fixes")
        XCTAssertTrue(
            instructions.lowercased().contains("output only"),
            "must forbid commentary so answers never replace the transcript"
        )
    }

    func testInstructionsIncludeDictionaryWordsWhenProvided() {
        let instructions = builder.instructions(dictionary: ["Trajekt", "gstack"])
        XCTAssertTrue(instructions.contains("Trajekt"))
        XCTAssertTrue(instructions.contains("gstack"))
    }

    func testInstructionsOmitDictionarySectionWhenEmpty() {
        XCTAssertFalse(builder.instructions().contains("spelling"))
    }

    func testInstructionsIncludeToneHintWhenProvided() {
        XCTAssertTrue(builder.instructions(toneHint: "casual, lowercase ok").contains("casual"))
    }

    func testUserPromptContainsTranscriptVerbatim() {
        let raw = "um so send it tuesday no wait wednesday"
        XCTAssertTrue(builder.userPrompt(rawTranscript: raw).contains(raw))
    }
}
