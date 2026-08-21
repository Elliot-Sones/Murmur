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

    func testOptionPDownClassifies() {
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .keyDown, keyCode: 35, flags: .maskAlternate, choice: .optionP
            ),
            .hotkeyDown
        )
    }

    func testOptionPAutorepeatIsIgnored() {
        XCTAssertNil(
            HotkeyEventClassifier.classify(
                type: .keyDown, keyCode: 35, flags: .maskAlternate, isAutorepeat: true, choice: .optionP
            )
        )
    }

    func testPKeyUpEndsOptionPHoldRegardlessOfModifierState() {
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .keyUp, keyCode: 35, flags: [], choice: .optionP
            ),
            .hotkeyUp,
            "release order must not matter, P up always ends the hold"
        )
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .keyUp, keyCode: 35, flags: .maskAlternate, choice: .optionP
            ),
            .hotkeyUp
        )
    }

    func testPlainPDoesNotTriggerOptionP() {
        XCTAssertNil(
            HotkeyEventClassifier.classify(
                type: .keyDown, keyCode: 35, flags: [], choice: .optionP
            )
        )
    }

    func testFnIsIgnoredWhenOptionPChosen() {
        XCTAssertNil(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 63, flags: .maskSecondaryFn, choice: .optionP
            )
        )
    }
}
