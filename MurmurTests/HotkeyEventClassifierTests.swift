import CoreGraphics
import XCTest
@testable import Murmur

final class HotkeyEventClassifierTests: XCTestCase {
    func testFnFlagTransitionMapsToDownAndUp() {
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 63, flags: .maskSecondaryFn, choice: .fn
            ),
            .hotkeyDown
        )
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 63, flags: [], choice: .fn
            ),
            .hotkeyUp
        )
    }

    func testRightCommandMapsToDownAndUp() {
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 54, flags: .maskCommand, choice: .rightCommand
            ),
            .hotkeyDown
        )
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 54, flags: [], choice: .rightCommand
            ),
            .hotkeyUp
        )
    }

    func testLeftCommandIsIgnoredForRightCommandChoice() {
        XCTAssertNil(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 55, flags: .maskCommand, choice: .rightCommand
            )
        )
    }

    func testEscapeKeyDownClassifies() {
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .keyDown, keyCode: 53, flags: [], choice: .fn
            ),
            .escape
        )
    }

    func testUnrelatedEventsClassifyAsNil() {
        XCTAssertNil(
            HotkeyEventClassifier.classify(type: .keyDown, keyCode: 12, flags: [], choice: .fn)
        )
        XCTAssertNil(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 63, flags: .maskSecondaryFn, choice: .rightCommand
            ),
            "fn must not trigger when right command is the chosen key"
        )
    }

    func testControlIDownClassifies() {
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .keyDown, keyCode: 34, flags: .maskControl, choice: .controlI
            ),
            .hotkeyDown
        )
    }

    func testControlIAutorepeatIsIgnored() {
        XCTAssertNil(
            HotkeyEventClassifier.classify(
                type: .keyDown, keyCode: 34, flags: .maskControl, isAutorepeat: true, choice: .controlI
            )
        )
    }

    func testIKeyUpEndsControlIHoldRegardlessOfModifierState() {
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .keyUp, keyCode: 34, flags: [], choice: .controlI
            ),
            .hotkeyUp,
            "release order must not matter, I up always ends the hold"
        )
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .keyUp, keyCode: 34, flags: .maskControl, choice: .controlI
            ),
            .hotkeyUp
        )
    }

    func testPlainIDoesNotTriggerControlI() {
        XCTAssertNil(
            HotkeyEventClassifier.classify(
                type: .keyDown, keyCode: 34, flags: [], choice: .controlI
            )
        )
    }

    func testFnIsIgnoredWhenControlIChosen() {
        XCTAssertNil(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 63, flags: .maskSecondaryFn, choice: .controlI
            )
        )
    }
}
