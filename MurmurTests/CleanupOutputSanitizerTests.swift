import XCTest
@testable import Murmur

final class CleanupOutputSanitizerTests: XCTestCase {
    func testNormalOutputPassesThroughUnchanged() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "I am available later today, but please let me know.",
                rawTranscript: "i am available later today but please let me know"
            ),
            "I am available later today, but please let me know."
        )
    }

    func testStripsPolishedVersionPreamble() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "Sure, here's a polished version of your text:\n\nI am available later today.",
                rawTranscript: "i am available later today"
            ),
            "I am available later today."
        )
    }

    func testStripsHereIsTheCleanedTranscriptPreamble() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "Here is the cleaned transcript:\nSend the report Wednesday.",
                rawTranscript: "um send the report wednesday"
            ),
            "Send the report Wednesday."
        )
    }

    func testKeepsColonLineTheUserActuallySaid() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "Here's the plan:\nShip on Friday.",
                rawTranscript: "here's the plan ship on friday"
            ),
            "Here's the plan:\nShip on Friday."
        )
    }

    func testStripsWrappingQuotes() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "\"Send the report Wednesday.\"",
                rawTranscript: "send the report wednesday"
            ),
            "Send the report Wednesday."
        )
    }

    func testStripsCodeFences() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "```\nSend the report Wednesday.\n```",
                rawTranscript: "send the report wednesday"
            ),
            "Send the report Wednesday."
        )
    }

    func testAnswerShapedOutputFallsBackToRaw() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "I don't know what is going on.",
                rawTranscript: "what is going on"
            ),
            "what is going on",
            "a model that answers the transcript must be discarded"
        )
    }

    func testFillerRemovalSurvivesTheOverlapGuard() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "Send the report Wednesday.",
                rawTranscript: "um send the report uh wednesday"
            ),
            "Send the report Wednesday."
        )
    }

    func testRewritePathSkipsTheOverlapGuard() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "Entirely different phrasing on purpose.",
                rawTranscript: "original casual words",
                enforceWordOverlap: false
            ),
            "Entirely different phrasing on purpose.",
            "command-mode rewrites legitimately change words"
        )
    }

    func testLiteralTranscriptTagsAreStrippedFromCleanupOutput() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "He added the code.<transcript>\nMore words.\n</transcript>",
                rawTranscript: "he added the code more words"
            ),
            "He added the code.\nMore words.",
            "the model must not be able to echo prompt delimiters into pasted text"
        )
    }

    func testTagStrippingIsSkippedOnTheRewritePath() {
        let selection = "keep <transcript> markers in code"
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "keep <transcript> markers in code",
                rawTranscript: selection,
                enforceWordOverlap: false
            ),
            selection,
            "selected code being rewritten may legitimately contain such tags"
        )
    }

    func testEmptyAfterSanitizingFallsBackToRaw() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "Here is the cleaned transcript:",
                rawTranscript: "send it"
            ),
            "send it"
        )
    }
}
