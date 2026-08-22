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
