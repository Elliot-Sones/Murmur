import XCTest
@testable import Murmur

final class WordErrorRateTests: XCTestCase {
    func testNormalizeLowercasesStripsPunctuationAndSplits() {
        XCTAssertEqual(
            WordErrorRate.normalize("Hello, World!  It's   me."),
            ["hello", "world", "it's", "me"]
        )
    }

    func testIdenticalTextScoresZero() {
        XCTAssertEqual(
            WordErrorRate.compute(reference: "the cat sat down", hypothesis: "The cat sat down."),
            0
        )
    }

    func testSingleDeletion() {
        XCTAssertEqual(
            WordErrorRate.compute(reference: "the cat sat", hypothesis: "the cat"),
            1.0 / 3.0,
            accuracy: 0.0001
        )
    }

    func testSubstitutionPlusInsertion() {
        XCTAssertEqual(
            WordErrorRate.compute(reference: "send it tuesday", hypothesis: "send at tuesday now"),
            2.0 / 3.0,
            accuracy: 0.0001
        )
    }

    func testEmptyReferenceEdgeCases() {
        XCTAssertEqual(WordErrorRate.compute(reference: "", hypothesis: ""), 0)
        XCTAssertEqual(WordErrorRate.compute(reference: "", hypothesis: "two words"), 2)
    }
}
