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

    func testAnswerReusingTheQuestionsWordsIsStillCaught() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "Um, can you do it for me? Yes, I can do that for you. What do you need help with?",
                rawTranscript: "um can you do it for me"
            ),
            "um can you do it for me",
            "output much longer than the transcript is an answer, not a cleanup"
        )
    }

    func testModestLengthGrowthIsAllowed() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "Send the report Wednesday, please.",
                rawTranscript: "send the report wednesday please"
            ),
            "Send the report Wednesday, please."
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

    func testSummarizedOutputFallsBackToRaw() {
        let transcript = "So basically what I am trying to say here is that the parser fails "
            + "because the buffer gets reused before the copy finishes and that is why "
            + "we see the corruption only under load in the second pass"
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "The parser fails because the buffer gets reused.",
                rawTranscript: transcript
            ),
            transcript,
            "a summary is built from the speaker's own words, so only a length floor catches it"
        )
    }

    func testFillerRemovalShrinkageIsStillAccepted() {
        let transcript = "so um basically the uh parser fails because like the buffer gets reused before the copy finishes"
        let cleaned = "Basically, the parser fails because the buffer gets reused before the copy finishes."
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(cleaned, rawTranscript: transcript),
            cleaned,
            "dropping um, uh, like, and so is the cleanup's whole job"
        )
    }

    func testRewritePathMayShortenFreely() {
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                "Shorter now.",
                rawTranscript: "please make this whole long selected paragraph much shorter now",
                enforceWordOverlap: false
            ),
            "Shorter now.",
            "command-mode rewrites legitimately condense"
        )
    }

    func testStripsAppendedLineTheUserNeverSpoke() {
        let transcript = "What does it even mean? Like, what do we do with it? "
            + "How do we distinguish me saying the wrong thing versus the voice model "
            + "getting the wrong thing? Right? So I don't know."
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                transcript + "\n\nIt is a NTangible, Clutch, NTerpret.",
                rawTranscript: transcript
            ),
            transcript,
            "the model recited the personal dictionary as a trailing sentence; a short appended line passes the whole-output guards"
        )
    }

    func testKeepsMultiLineOutputMadeOfSpokenWords() {
        let transcript = "shopping list first eggs second milk third bread"
        let formatted = "Shopping list:\n1. Eggs\n2. Milk\n3. Bread"
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(formatted, rawTranscript: transcript),
            formatted,
            "dictated lists legitimately become short multi-line output"
        )
    }

    func testRewritePathKeepsNovelLines() {
        let output = "Rewritten intro.\nA second novel line written by the rewrite model."
        XCTAssertEqual(
            CleanupOutputSanitizer.sanitize(
                output,
                rawTranscript: "make this an intro with a second line",
                enforceWordOverlap: false
            ),
            output,
            "command-mode rewrites legitimately produce lines of new words"
        )
    }
}
