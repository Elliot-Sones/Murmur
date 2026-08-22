import XCTest
@testable import Murmur

final class MedianTests: XCTestCase {
    func testMedianOfValues() {
        XCTAssertNil(Median.of([]))
        XCTAssertEqual(Median.of([5]), 5)
        XCTAssertEqual(Median.of([9, 1, 3]), 3)
        XCTAssertEqual(Median.of([9, 1, 5, 3]), 4)
    }
}
