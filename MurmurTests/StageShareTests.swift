import XCTest
@testable import Murmur

final class StageShareTests: XCTestCase {
    func testSharesAreProportionalAndSumToOne() {
        let shares = StageShare.shares([100, 300, 100])
        XCTAssertEqual(shares.count, 3)
        XCTAssertEqual(shares[0], 0.2, accuracy: 0.0001)
        XCTAssertEqual(shares[1], 0.6, accuracy: 0.0001)
        XCTAssertEqual(shares[2], 0.2, accuracy: 0.0001)
        XCTAssertEqual(shares.reduce(0, +), 1.0, accuracy: 0.0001)
    }

    func testZeroTotalGivesAllZeros() {
        XCTAssertEqual(StageShare.shares([0, 0, 0]), [0, 0, 0])
    }

    func testNegativeValuesCountAsZero() {
        let shares = StageShare.shares([-50, 100, 100])
        XCTAssertEqual(shares[0], 0)
        XCTAssertEqual(shares[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(shares[2], 0.5, accuracy: 0.0001)
    }

    func testEmptyInputGivesEmptyOutput() {
        XCTAssertEqual(StageShare.shares([]), [])
    }
}
