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

    func testUserPromptIsTheBareTranscriptAndNothingElse() {
        let raw = "um so send it tuesday no wait wednesday"
        XCTAssertEqual(
            builder.userPrompt(rawTranscript: raw), raw,
            "any scaffolding in the user message eventually leaks into output"
        )
    }

    func testInstructionsCarryTheNeverAnswerRule() {
        XCTAssertTrue(
            builder.instructions().lowercased().contains("never answer"),
            "questions in the transcript must never be answered"
        )
    }

    func testInstructionsIncludeDestinationWhenProvided() {
        let instructions = builder.instructions(destination: "Mail (Re: Budget review)")
        XCTAssertTrue(instructions.contains("Mail (Re: Budget review)"))
    }

    func testInstructionsOmitDestinationWhenAbsent() {
        XCTAssertFalse(builder.instructions().contains("Destination"))
    }

    func testDictionaryRuleForbidsAddingTheWords() {
        let instructions = builder.instructions(dictionary: ["NTangible", "Clutch"])
        XCTAssertTrue(
            instructions.contains("Never add them"),
            "the model once recited the whole dictionary as its own trailing sentence"
        )
    }
}
