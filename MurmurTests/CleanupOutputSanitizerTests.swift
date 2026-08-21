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
