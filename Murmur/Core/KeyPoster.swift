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

    /// Waits until the user's physical modifier keys are all up. A synthetic
    /// Cmd+key posted while a hotkey's modifier is still held reaches the app
    /// with that modifier merged in (combined session state), turning Cmd+C
    /// into Cmd+Opt+C, which most apps ignore.
    static func waitForModifierRelease(timeoutMs: Int = 800) async {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
        while ContinuousClock.now < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(modifiers).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
