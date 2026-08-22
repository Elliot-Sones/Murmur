import XCTest
@testable import Murmur

final class ClipboardWatchLogicTests: XCTestCase {
    func testFirstObservationOnlyBaselines() {
        var logic = ClipboardWatchLogic()
        XCTAssertFalse(
            logic.observe(changeCount: 5, axSeesSelection: false, focusedRoleIsTexty: true),
            "whatever was on the clipboard before the pill turned on is old news"
        )
    }

    func testUnchangedCountStaysQuiet() {
        var logic = ClipboardWatchLogic()
        _ = logic.observe(changeCount: 5, axSeesSelection: false, focusedRoleIsTexty: true)
        XCTAssertFalse(logic.observe(changeCount: 5, axSeesSelection: false, focusedRoleIsTexty: true))
    }

    func testFreshCopyInAxBlindTextAppSpeaks() {
        var logic = ClipboardWatchLogic()
        _ = logic.observe(changeCount: 5, axSeesSelection: false, focusedRoleIsTexty: true)
        XCTAssertTrue(logic.observe(changeCount: 6, axSeesSelection: false, focusedRoleIsTexty: true))
    }

    func testCopyWhereAxSeesSelectionIsThePollersJob() {
        var logic = ClipboardWatchLogic()
        _ = logic.observe(changeCount: 5, axSeesSelection: false, focusedRoleIsTexty: true)
        XCTAssertFalse(
            logic.observe(changeCount: 6, axSeesSelection: true, focusedRoleIsTexty: true),
            "the selection poller already reads AX-visible apps; speaking the copy too would double up"
        )
    }

    func testCopyOutsideTextContextsStaysQuiet() {
        var logic = ClipboardWatchLogic()
        _ = logic.observe(changeCount: 5, axSeesSelection: false, focusedRoleIsTexty: true)
        XCTAssertFalse(
            logic.observe(changeCount: 6, axSeesSelection: false, focusedRoleIsTexty: false),
            "copying files in Finder must not narrate filenames"
        )
    }

    func testIgnoredCountsAreSkippedOnce() {
        var logic = ClipboardWatchLogic()
        _ = logic.observe(changeCount: 5, axSeesSelection: false, focusedRoleIsTexty: true)
        logic.ignore(changeCount: 6)
        XCTAssertFalse(
            logic.observe(changeCount: 6, axSeesSelection: false, focusedRoleIsTexty: true),
            "our own clipboard restores are not user copies"
        )
        XCTAssertTrue(
            logic.observe(changeCount: 7, axSeesSelection: false, focusedRoleIsTexty: true),
            "the next real copy still speaks"
        )
    }

    func testMissedCountsStillTriggerOnce() {
        var logic = ClipboardWatchLogic()
        _ = logic.observe(changeCount: 5, axSeesSelection: false, focusedRoleIsTexty: true)
        XCTAssertTrue(
            logic.observe(changeCount: 9, axSeesSelection: false, focusedRoleIsTexty: true),
            "several copies between polls collapse into one speak of the latest"
        )
        XCTAssertFalse(logic.observe(changeCount: 9, axSeesSelection: false, focusedRoleIsTexty: true))
    }
}
