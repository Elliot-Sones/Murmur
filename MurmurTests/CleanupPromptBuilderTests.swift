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
        XCTAssertTrue(
            instructions.lowercased().contains("fewest edits"),
            "must demand minimal editing so the speaker's words survive"
        )
    }

    func testToneHintIsScopedToPunctuationAndCasingNotRewording() {
        let instructions = builder.instructions(toneHint: "very casual")
        XCTAssertTrue(
            instructions.lowercased().contains("never reword"),
            "tone must not license paraphrasing"
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

    func testUserPromptIncludesDestinationWhenProvided() {
        let prompt = builder.userPrompt(
            rawTranscript: "sounds good",
            appName: "Mail",
            windowTitle: "Re: Budget review"
        )
        XCTAssertTrue(prompt.contains("Mail"))
        XCTAssertTrue(prompt.contains("Re: Budget review"))
    }

    func testUserPromptOmitsDestinationWhenAbsent() {
        let prompt = builder.userPrompt(rawTranscript: "sounds good")
        XCTAssertFalse(prompt.contains("Destination"))
    }
}
