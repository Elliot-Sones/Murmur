import XCTest
@testable import Murmur

final class CorrectionBlameTests: XCTestCase {
    func testAppendedWordsBlameCleanup() {
        XCTAssertEqual(
            CorrectionBlame.classify(
                raw: "what do we do with it so i don't know",
                cleaned: "What do we do with it? So I don't know.\n\nIt is a NTangible, Clutch, NTerpret.",
                corrected: "What do we do with it? So I don't know."
            ),
            .cleanup,
            "the correction is closer to the raw transcript than to the model output"
        )
    }

    func testMisheardWordBlamesTranscription() {
        XCTAssertEqual(
            CorrectionBlame.classify(
                raw: "the clutch model is ready",
                cleaned: "The clutch model is ready.",
                corrected: "The crutch model is ready."
            ),
            .transcription,
            "cleanup faithfully kept a recognizer mistake"
        )
    }

    func testResidualErrorAfterPartialFixBlamesTranscription() {
        XCTAssertEqual(
            CorrectionBlame.classify(
                raw: "the the clutch model is ready",
                cleaned: "The clutch model is ready.",
                corrected: "The crutch model is ready."
            ),
            .transcription,
            "cleanup improved things; what remains traces back to the recognizer"
        )
    }

    func testFreeRewriteIsRephrasedNotAModelError() {
        XCTAssertEqual(
            CorrectionBlame.classify(
                raw: "send the report tomorrow",
                cleaned: "Send the report tomorrow.",
                corrected: "Actually let's ship it next week."
            ),
            .rephrased,
            "far from both raw and cleaned means the user changed their mind"
        )
    }

    func testPunctuationOnlyEditIsFormatting() {
        XCTAssertEqual(
            CorrectionBlame.classify(
                raw: "hello world",
                cleaned: "Hello world",
                corrected: "Hello, world!"
            ),
            .formatting,
            "same words, different punctuation"
        )
    }

    func testExplanationsAreDistinct() {
        let all: [CorrectionBlame] = [.cleanup, .transcription, .rephrased, .formatting]
        XCTAssertEqual(
            Set(all.map(\.explanation)).count,
            all.count,
            "each cause needs its own history label"
        )
    }
}
