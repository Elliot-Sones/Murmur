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

    func testShortTapAloneCancelsAfterWindow() {
        var machine = HotkeyStateMachine()
        XCTAssertEqual(machine.handle(.hotkeyDown(0)), [.startRecording])
        XCTAssertEqual(machine.handle(.hotkeyUp(0.1)), [])
        XCTAssertTrue(machine.isCapturing, "still waiting for a possible second tap")
        XCTAssertEqual(machine.handle(.tick(0.9)), [.cancelRecording])
        XCTAssertFalse(machine.isCapturing)
    }

    func testDoubleTapEntersHandsFreeAndNextPressFinishes() {
        var machine = HotkeyStateMachine()
        XCTAssertEqual(machine.handle(.hotkeyDown(0)), [.startRecording])
        XCTAssertEqual(machine.handle(.hotkeyUp(0.1)), [])
        XCTAssertEqual(machine.handle(.hotkeyDown(0.3)), [])
        XCTAssertEqual(machine.handle(.hotkeyUp(0.4)), [])
        XCTAssertTrue(machine.isCapturing, "hands-free keeps recording")
        XCTAssertEqual(machine.handle(.tick(5)), [])
        XCTAssertTrue(machine.isCapturing, "tick must not end hands-free")
        XCTAssertEqual(machine.handle(.hotkeyDown(6)), [.finishRecording])
        XCTAssertEqual(machine.handle(.hotkeyUp(6.1)), [])
        XCTAssertFalse(machine.isCapturing)
    }

    func testLateSecondPressRestartsInsteadOfHandsFree() {
        var machine = HotkeyStateMachine()
        XCTAssertEqual(machine.handle(.hotkeyDown(0)), [.startRecording])
        XCTAssertEqual(machine.handle(.hotkeyUp(0.1)), [])
        XCTAssertEqual(machine.handle(.hotkeyDown(2.0)), [.cancelRecording, .startRecording])
        XCTAssertEqual(machine.handle(.hotkeyUp(3.0)), [.finishRecording])
    }

    func testEscapeCancelsWhileHolding() {
        var machine = HotkeyStateMachine()
        XCTAssertEqual(machine.handle(.hotkeyDown(0)), [.startRecording])
        XCTAssertEqual(machine.handle(.escapeDown), [.cancelRecording])
        XCTAssertFalse(machine.isCapturing)
        XCTAssertEqual(machine.handle(.hotkeyUp(0.5)), [], "release after cancel is ignored")
    }

    func testEscapeCancelsHandsFree() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.hotkeyDown(0))
        _ = machine.handle(.hotkeyUp(0.1))
        _ = machine.handle(.hotkeyDown(0.3))
        _ = machine.handle(.hotkeyUp(0.4))
        XCTAssertEqual(machine.handle(.escapeDown), [.cancelRecording])
        XCTAssertFalse(machine.isCapturing)
    }

    func testIdleIgnoresEscapeUpAndTick() {
        var machine = HotkeyStateMachine()
        XCTAssertEqual(machine.handle(.escapeDown), [])
        XCTAssertEqual(machine.handle(.hotkeyUp(1)), [])
        XCTAssertEqual(machine.handle(.tick(2)), [])
        XCTAssertFalse(machine.isCapturing)
    }
}
