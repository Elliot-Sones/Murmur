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

    func testControlOptionChordDownWhenBothModifiersArrive() {
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 61, flags: [.maskControl, .maskAlternate],
                chordActive: false, choice: .controlOption
            ),
            .hotkeyDown
        )
    }

    func testControlOptionChordUpWhenEitherModifierReleases() {
        XCTAssertEqual(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 59, flags: .maskAlternate,
                chordActive: true, choice: .controlOption
            ),
            .hotkeyUp,
            "releasing control while option is still down must end the hold"
        )
    }

    func testControlOptionSingleModifierDoesNotTrigger() {
        XCTAssertNil(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 59, flags: .maskControl,
                chordActive: false, choice: .controlOption
            )
        )
        XCTAssertNil(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 61, flags: .maskAlternate,
                chordActive: false, choice: .controlOption
            )
        )
    }

    func testControlOptionNoRepeatWhileChordHeld() {
        XCTAssertNil(
            HotkeyEventClassifier.classify(
                type: .flagsChanged, keyCode: 56, flags: [.maskControl, .maskAlternate, .maskShift],
                chordActive: true, choice: .controlOption
            ),
            "extra modifier changes while the chord is held must not re-trigger"
        )
    }

    func testCommandRightOptionIgnoredWhileControlHeld() {
        XCTAssertNil(
            HotkeyEventClassifier.classifyCommand(
                type: .flagsChanged, keyCode: 61, flags: [.maskControl, .maskAlternate],
                choice: .rightOption
            ),
            "control plus option belongs to the dictation chord, never command mode"
        )
    }

    func testCommandRightOptionFlagTransitions() {
        XCTAssertEqual(
            HotkeyEventClassifier.classifyCommand(
                type: .flagsChanged, keyCode: 61, flags: .maskAlternate, choice: .rightOption
            ),
            .hotkeyDown
        )
        XCTAssertEqual(
            HotkeyEventClassifier.classifyCommand(
                type: .flagsChanged, keyCode: 61, flags: [], choice: .rightOption
            ),
            .hotkeyUp
        )
    }

    func testCommandLeftOptionIsIgnored() {
        XCTAssertNil(
            HotkeyEventClassifier.classifyCommand(
                type: .flagsChanged, keyCode: 58, flags: .maskAlternate, choice: .rightOption
            )
        )
    }

    func testOptionEscapeIsTheSpeakHotkey() {
        XCTAssertTrue(
            HotkeyEventClassifier.isSpeakSelectionHotkey(
                type: .keyDown, keyCode: 53, flags: .maskAlternate
            )
        )
    }

    func testSpeakHotkeyRejectsOtherShapes() {
        XCTAssertFalse(
            HotkeyEventClassifier.isSpeakSelectionHotkey(type: .keyDown, keyCode: 53, flags: []),
            "plain Esc belongs to cancel flows"
        )
        XCTAssertFalse(
            HotkeyEventClassifier.isSpeakSelectionHotkey(
                type: .keyDown, keyCode: 53, flags: .maskAlternate, isAutorepeat: true
            ),
            "holding the combo must fire once, not once per key repeat"
        )
        XCTAssertFalse(
            HotkeyEventClassifier.isSpeakSelectionHotkey(
                type: .keyUp, keyCode: 53, flags: .maskAlternate
            )
        )
        XCTAssertFalse(
            HotkeyEventClassifier.isSpeakSelectionHotkey(
                type: .keyDown, keyCode: 53, flags: [.maskAlternate, .maskCommand]
            ),
            "Cmd+Option+Esc is Force Quit; never touch it"
        )
        XCTAssertFalse(
            HotkeyEventClassifier.isSpeakSelectionHotkey(
                type: .keyDown, keyCode: 53, flags: [.maskAlternate, .maskControl]
            )
        )
        XCTAssertFalse(
            HotkeyEventClassifier.isSpeakSelectionHotkey(
                type: .keyDown, keyCode: 0, flags: .maskAlternate
            )
        )
    }

    func testCommandControlOCombo() {
        XCTAssertEqual(
            HotkeyEventClassifier.classifyCommand(
                type: .keyDown, keyCode: 31, flags: .maskControl, choice: .controlO
            ),
            .hotkeyDown
        )
        XCTAssertEqual(
            HotkeyEventClassifier.classifyCommand(
                type: .keyUp, keyCode: 31, flags: [], choice: .controlO
            ),
            .hotkeyUp
        )
        XCTAssertNil(
            HotkeyEventClassifier.classifyCommand(
                type: .keyDown, keyCode: 31, flags: .maskControl, isAutorepeat: true, choice: .controlO
            )
        )
        XCTAssertNil(
            HotkeyEventClassifier.classifyCommand(
                type: .keyDown, keyCode: 31, flags: [], choice: .controlO
            ),
            "plain o must not trigger command mode"
        )
    }

}
