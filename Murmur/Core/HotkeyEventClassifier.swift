import CoreGraphics

enum ClassifiedKeyEvent: Equatable {
    case hotkeyDown
    case hotkeyUp
    case escape
}

/// Maps raw CGEvent facts to hotkey events for the configured dictation key.
enum HotkeyEventClassifier {
    private static let fnKeyCode: Int64 = 63
    private static let rightCommandKeyCode: Int64 = 54
    private static let escapeKeyCode: Int64 = 53

    static func classify(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        choice: HotkeyChoice
    ) -> ClassifiedKeyEvent? {
        if type == .keyDown, keyCode == escapeKeyCode {
            return .escape
        }
        guard type == .flagsChanged else { return nil }

        switch choice {
        case .fn:
            guard keyCode == fnKeyCode else { return nil }
            return flags.contains(.maskSecondaryFn) ? .hotkeyDown : .hotkeyUp
        case .rightCommand:
            guard keyCode == rightCommandKeyCode else { return nil }
            return flags.contains(.maskCommand) ? .hotkeyDown : .hotkeyUp
        }
    }
}
