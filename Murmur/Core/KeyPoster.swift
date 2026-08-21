import CoreGraphics

/// Posts synthetic Command+key events (paste, copy) to the focused app.
@MainActor
enum KeyPoster {
    static let vKey: CGKeyCode = 9
    static let cKey: CGKeyCode = 8

    static func postCommandKey(_ virtualKey: CGKeyCode) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        for keyDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown
            ) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }
}
