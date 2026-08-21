import CoreGraphics

enum ClassifiedKeyEvent: Equatable {
    case hotkeyDown
    case hotkeyUp
    case escape
}

/// What a keystroke means while a dictation waits in the review editor.
enum ReviewKeyAction: Equatable {
    case accept
    case cancel
}

/// Maps raw CGEvent facts to hotkey events for the configured dictation key.
enum HotkeyEventClassifier {
    static let fnKeyCode: Int64 = 63
    static let rightCommandKeyCode: Int64 = 54
    static let rightOptionKeyCode: Int64 = 61
    static let escapeKeyCode: Int64 = 53
    static let iKeyCode: Int64 = 34
    static let oKeyCode: Int64 = 31
    static let returnKeyCode: Int64 = 36
    static let keypadEnterKeyCode: Int64 = 76

    /// Classifies keystrokes while a review is pending and the HUD editor is
    /// the key window. Plain Return/Enter accepts, plain Esc cancels; any
    /// modifier passes the key through so the field can handle line breaks.
    static func classifyReview(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags
    ) -> ReviewKeyAction? {
        guard type == .keyDown else { return nil }
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        guard flags.intersection(modifiers).isEmpty else { return nil }
        switch keyCode {
        case returnKeyCode, keypadEnterKeyCode: return .accept
        case escapeKeyCode: return .cancel
        default: return nil
        }
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
