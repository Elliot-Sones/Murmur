import XCTest
@testable import Murmur

final class HotkeyStateMachineTests: XCTestCase {
    func testHoldAndReleaseFinishesRecording() {
        var machine = HotkeyStateMachine()
        XCTAssertEqual(machine.handle(.hotkeyDown(0)), [.startRecording])
        XCTAssertTrue(machine.isCapturing)
        XCTAssertEqual(machine.handle(.hotkeyUp(0.8)), [.finishRecording])
        XCTAssertFalse(machine.isCapturing)
    }

    func testTapTogglesOnAndKeepsListening() {
        var machine = HotkeyStateMachine()
        XCTAssertEqual(machine.handle(.hotkeyDown(0)), [.startRecording])
        XCTAssertEqual(machine.handle(.hotkeyUp(0.1)), [], "a tap locks listening on, no decision window")
        XCTAssertTrue(machine.isCapturing)
    }

    func testSecondTapFinishes() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.hotkeyDown(0))
        _ = machine.handle(.hotkeyUp(0.1))
        XCTAssertEqual(machine.handle(.hotkeyDown(3)), [.finishRecording])
        XCTAssertEqual(machine.handle(.hotkeyUp(3.1)), [], "the finishing press's release is ignored")
        XCTAssertFalse(machine.isCapturing)
    }

    func testQuickSecondTapAlsoFinishes() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.hotkeyDown(0))
        _ = machine.handle(.hotkeyUp(0.1))
        XCTAssertEqual(
            machine.handle(.hotkeyDown(0.3)), [.finishRecording],
            "tap-tap means start then stop; there is no double-tap gesture anymore"
        )
    }

    func testEscapeCancelsWhileHolding() {
        var machine = HotkeyStateMachine()
        XCTAssertEqual(machine.handle(.hotkeyDown(0)), [.startRecording])
        XCTAssertEqual(machine.handle(.escapeDown), [.cancelRecording])
        XCTAssertFalse(machine.isCapturing)
        XCTAssertEqual(machine.handle(.hotkeyUp(0.5)), [], "release after cancel is ignored")
    }

    func testEscapeCancelsLockedListening() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.hotkeyDown(0))
        _ = machine.handle(.hotkeyUp(0.1))
        XCTAssertEqual(machine.handle(.escapeDown), [.cancelRecording])
        XCTAssertFalse(machine.isCapturing)
    }

    func testIdleIgnoresStrayEvents() {
        var machine = HotkeyStateMachine()
        XCTAssertEqual(machine.handle(.escapeDown), [])
        XCTAssertEqual(machine.handle(.hotkeyUp(1)), [])
        XCTAssertFalse(machine.isCapturing)
    }
}
