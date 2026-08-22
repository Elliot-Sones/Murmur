import CoreGraphics

enum ClassifiedKeyEvent: Equatable {
    case hotkeyDown
    case hotkeyUp
    case escape
}


/// Maps raw CGEvent facts to hotkey events for the configured dictation key.
enum HotkeyEventClassifier {
    static let fnKeyCode: Int64 = 63
    static let rightCommandKeyCode: Int64 = 54
    static let rightOptionKeyCode: Int64 = 61
    static let escapeKeyCode: Int64 = 53
    static let iKeyCode: Int64 = 34
    static let oKeyCode: Int64 = 31

    /// Option+Esc (macOS's own Speak Selection combo) reads the current
    /// selection aloud, with the copy fallback for AX-blind apps.
    /// Cmd/Ctrl variants are excluded; Cmd+Option+Esc is Force Quit.
    static func isSpeakSelectionHotkey(
        type: CGEventType, keyCode: Int64, flags: CGEventFlags, isAutorepeat: Bool = false
    ) -> Bool {
        type == .keyDown
            && !isAutorepeat
            && keyCode == escapeKeyCode
            && flags.contains(.maskAlternate)
            && !flags.contains(.maskCommand)
            && !flags.contains(.maskControl)
    }

    /// Ctrl+Esc flips speak-on-highlight mode, exactly like clicking the
    /// pill. Plain Esc stops or cancels things; Option+Esc speaks on demand.
    static func isToggleSpeakModeHotkey(
        type: CGEventType, keyCode: Int64, flags: CGEventFlags, isAutorepeat: Bool = false
    ) -> Bool {
        type == .keyDown
            && !isAutorepeat
            && keyCode == escapeKeyCode
            && flags.contains(.maskControl)
            && !flags.contains(.maskCommand)
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskShift)
    }

    /// Classifies events for the command-mode hotkey. Escape is handled by
    /// `classify`; this only reports the command key itself.
    static func classifyCommand(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        isAutorepeat: Bool = false,
        choice: CommandHotkeyChoice
    ) -> ClassifiedKeyEvent? {
        switch choice {
        case .rightOption:
            guard type == .flagsChanged, keyCode == rightOptionKeyCode else { return nil }
            // Control plus option belongs to the dictation chord.
            guard !flags.contains(.maskControl) else { return nil }
            return flags.contains(.maskAlternate) ? .hotkeyDown : .hotkeyUp
        case .controlO:
            guard keyCode == oKeyCode, !isAutorepeat else { return nil }
            switch type {
            case .keyDown where flags.contains(.maskControl): return .hotkeyDown
            case .keyUp: return .hotkeyUp
            default: return nil
            }
        }
    }

    static func classify(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        isAutorepeat: Bool = false,
        chordActive: Bool = false,
        choice: HotkeyChoice
    ) -> ClassifiedKeyEvent? {
        if type == .keyDown, keyCode == escapeKeyCode {
            return .escape
        }

        switch choice {
        case .fn:
            guard type == .flagsChanged, keyCode == fnKeyCode else { return nil }
            return flags.contains(.maskSecondaryFn) ? .hotkeyDown : .hotkeyUp
        case .rightCommand:
            guard type == .flagsChanged, keyCode == rightCommandKeyCode else { return nil }
            return flags.contains(.maskCommand) ? .hotkeyDown : .hotkeyUp
        case .controlI:
            guard keyCode == iKeyCode, !isAutorepeat else { return nil }
            switch type {
            case .keyDown where flags.contains(.maskControl): return .hotkeyDown
            case .keyUp: return .hotkeyUp
            default: return nil
            }
        case .controlOption:
            guard type == .flagsChanged else { return nil }
            let active = flags.contains(.maskControl) && flags.contains(.maskAlternate)
            if active, !chordActive { return .hotkeyDown }
            if !active, chordActive { return .hotkeyUp }
            return nil
        }
    }
}
