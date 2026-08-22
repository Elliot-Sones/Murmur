import XCTest
@testable import Murmur

final class SelectionWatcherLogicTests: XCTestCase {
    func testFirstSightingWaitsForStability() {
        var logic = SelectionWatcherLogic()
        XCTAssertNil(logic.observe("hello world"), "a selection mid-drag must not speak yet")
        XCTAssertEqual(logic.observe("hello world"), "hello world", "same selection twice is stable")
    }

    func testHeldSelectionSpeaksOnlyOnce() {
        var logic = SelectionWatcherLogic()
        _ = logic.observe("hello")
        XCTAssertEqual(logic.observe("hello"), "hello")
        XCTAssertNil(logic.observe("hello"))
        XCTAssertNil(logic.observe("hello"))
    }

    func testClearingThenReselectingSpeaksAgain() {
        var logic = SelectionWatcherLogic()
        _ = logic.observe("hello")
        _ = logic.observe("hello")
        XCTAssertNil(logic.observe(nil))
        XCTAssertNil(logic.observe("hello"), "stability starts over after a clear")
        XCTAssertEqual(logic.observe("hello"), "hello")
    }

    func testChangedSelectionNeedsItsOwnStability() {
        var logic = SelectionWatcherLogic()
        _ = logic.observe("first")
        _ = logic.observe("first")
        XCTAssertNil(logic.observe("first longer"), "growing selection is still being dragged")
        XCTAssertEqual(logic.observe("first longer"), "first longer")
    }

    func testEmptyAndWhitespaceNeverSpeak() {
        var logic = SelectionWatcherLogic()
        XCTAssertNil(logic.observe(""))
        XCTAssertNil(logic.observe(""))
        XCTAssertNil(logic.observe("   \n"))
        XCTAssertNil(logic.observe("   \n"))
    }

    func testLongSelectionIsTruncated() {
        var logic = SelectionWatcherLogic()
        let long = String(repeating: "word ", count: 500)
        _ = logic.observe(long)
        let spoken = logic.observe(long)
        XCTAssertNotNil(spoken)
        XCTAssertLessThanOrEqual(spoken?.count ?? 0, SelectionWatcherLogic.maxCharacters)
    }

    func testSettleSpeaksImmediatelyWithoutStability() {
        var logic = SelectionWatcherLogic()
        XCTAssertEqual(
            logic.settle("picked at mouse up"), "picked at mouse up",
            "mouse release is itself the settle signal; no second poll needed"
        )
    }

    func testSettleDoesNotRepeatTheLastSpokenText() {
        var logic = SelectionWatcherLogic()
        _ = logic.settle("hello")
        XCTAssertNil(logic.settle("hello"))
        XCTAssertNil(logic.observe("hello"), "polling right after must not re-speak either")
    }

    func testSettleIgnoresEmptyAndRearmsNothing() {
        var logic = SelectionWatcherLogic()
        _ = logic.settle("hello")
        XCTAssertNil(logic.settle("  \n"))
        XCTAssertNil(logic.settle("hello"), "empty settle must not clear the no-repeat guard")
    }

    func testObserveClearStillRearmsAfterSettle() {
        var logic = SelectionWatcherLogic()
        _ = logic.settle("hello")
        _ = logic.observe(nil)
        XCTAssertEqual(logic.settle("hello"), "hello", "deselecting re-arms the same text")
    }
}
