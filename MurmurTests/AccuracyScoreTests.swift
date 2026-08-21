import XCTest
@testable import Murmur

final class AccuracyScoreTests: XCTestCase {
    func testIdenticalModuloCaseAndPunctuationScoresHundred() {
        XCTAssertEqual(
            AccuracyScore.percent(
                inserted: "Send the report Wednesday.",
                corrected: "send the report wednesday"
            ),
            100,
            accuracy: 0.001
        )
    }

    func testOneWrongWordOfFourScoresSeventyFive() {
        XCTAssertEqual(
            AccuracyScore.percent(
                inserted: "send the report wednesday",
                corrected: "send the report thursday"
            ),
            75,
            accuracy: 0.001
        )
    }

    func testCompletelyWrongOutputClampsAtZero() {
        XCTAssertEqual(
            AccuracyScore.percent(
                inserted: "entirely unrelated words appear here today",
                corrected: "yes"
            ),
            0,
            accuracy: 0.001
        )
    }

    func testMedianOfValues() {
        XCTAssertNil(Median.of([]))
        XCTAssertEqual(Median.of([5]), 5)
        XCTAssertEqual(Median.of([9, 1, 3]), 3)
        XCTAssertEqual(Median.of([9, 1, 5, 3]), 4)
    }
}
