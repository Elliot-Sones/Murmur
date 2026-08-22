import XCTest
@testable import Murmur

final class SentenceSplitterTests: XCTestCase {
    func testSplitsOnSentencePunctuation() {
        XCTAssertEqual(
            SentenceSplitter.split("Hello world. How are you? Great!"),
            ["Hello world.", "How are you?", "Great!"]
        )
    }

    func testNewlinesBreakSentencesEvenWithoutPunctuation() {
        XCTAssertEqual(
            SentenceSplitter.split("First bullet\nSecond bullet\nThird"),
            ["First bullet", "Second bullet", "Third"],
            "list lines rarely end with periods but must be separate chunks"
        )
    }

    func testCollapsesWhitespaceAndDropsEmpties() {
        XCTAssertEqual(
            SentenceSplitter.split("  One.   \n\n  Two.  "),
            ["One.", "Two."]
        )
    }

    func testAbbreviationsDoNotOverSplit() {
        XCTAssertEqual(
            SentenceSplitter.split("Dr. Smith arrived at 3 p.m. and left."),
            ["Dr. Smith arrived at 3 p.m. and left."]
        )
    }

    func testSingleWordSurvives() {
        XCTAssertEqual(SentenceSplitter.split("Hello"), ["Hello"])
        XCTAssertEqual(SentenceSplitter.split(""), [])
    }

    func testFastStartSplitsALongOpenerAtItsFirstClause() {
        let long = "When the opening sentence rambles on for quite a while, the reader waits too long for first audio."
        let result = SentenceSplitter.fastStart([long, "Second."])
        XCTAssertEqual(
            result,
            [
                "When the opening sentence rambles on for quite a while,",
                "the reader waits too long for first audio.",
                "Second.",
            ]
        )
    }

    func testFastStartLeavesShortOpenersAlone() {
        XCTAssertEqual(
            SentenceSplitter.fastStart(["Short opener.", "Second."]),
            ["Short opener.", "Second."]
        )
    }

    func testFastStartWithoutClauseBoundaryLeavesItAlone() {
        let long = String(repeating: "word ", count: 20).trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(SentenceSplitter.fastStart([long]), [long])
    }

    func testFastStartIgnoresTooEarlyCommas() {
        let long = "Yes, this opener has an early comma but no later clause boundary at all in the rest of it"
        XCTAssertEqual(
            SentenceSplitter.fastStart([long]), [long],
            "splitting after two words would sound choppy, not fast"
        )
    }

    func testFastStartOnEmptyListIsEmpty() {
        XCTAssertEqual(SentenceSplitter.fastStart([]), [])
    }
}

final class ReaderSpeedTests: XCTestCase {
    func testStepsAreAscendingAndIncludeNormal() {
        XCTAssertEqual(ReaderSpeed.steps, ReaderSpeed.steps.sorted())
        XCTAssertTrue(ReaderSpeed.steps.contains(1.0))
    }

    func testStepsReachThreeX() {
        XCTAssertEqual(ReaderSpeed.steps.max(), 3.0, "time-pitch playback allows beyond AVAudioPlayer's 2x cap")
        XCTAssertTrue(ReaderSpeed.steps.contains(2.5))
    }

    func testNextCyclesThroughSteps() {
        XCTAssertEqual(ReaderSpeed.next(after: 1.0), 1.25, accuracy: 0.001)
        XCTAssertEqual(ReaderSpeed.next(after: 2.0), 2.5, accuracy: 0.001)
        XCTAssertEqual(ReaderSpeed.next(after: 3.0), 0.75, accuracy: 0.001, "top wraps to bottom")
        XCTAssertEqual(ReaderSpeed.next(after: 3.7), 0.75, accuracy: 0.001, "unknown speeds reset")
    }

    func testLabelFormatting() {
        XCTAssertEqual(ReaderSpeed.label(for: 1.0), "1×")
        XCTAssertEqual(ReaderSpeed.label(for: 1.25), "1.25×")
        XCTAssertEqual(ReaderSpeed.label(for: 2.5), "2.5×")
        XCTAssertEqual(ReaderSpeed.label(for: 3.0), "3×")
    }
}
