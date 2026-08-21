import XCTest
@testable import Murmur

final class ReviewOutcomeTests: XCTestCase {
    func testUnchangedAcceptYieldsNoCorrection() {
        XCTAssertNil(ReviewOutcome.correction(model: "Send it Wednesday.", final: "Send it Wednesday."))
    }

    func testEditedAcceptYieldsTheFinalTextAsCorrection() {
        XCTAssertEqual(
            ReviewOutcome.correction(model: "Send it Wednesday.", final: "Send it Thursday."),
            "Send it Thursday."
        )
    }

    func testWhitespaceOnlyDifferencesAreNotCorrections() {
        XCTAssertNil(ReviewOutcome.correction(model: "Send it.", final: "  Send it.  "))
    }
}
