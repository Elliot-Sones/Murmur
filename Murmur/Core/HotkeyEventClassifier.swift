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
    static let escapeKeyCode: Int64 = 53
    static let iKeyCode: Int64 = 34

    static func classify(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        isAutorepeat: Bool = false,
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
        }
    }
}
