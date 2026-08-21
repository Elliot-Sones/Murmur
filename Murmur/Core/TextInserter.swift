import AppKit

/// Pastes text into the focused app: snapshot clipboard, paste, restore clipboard.
@MainActor
final class TextInserter {
    func insert(_ text: String, restoreDelayMs: Int) async {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(capturing: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCommandV()

        try? await Task.sleep(for: .milliseconds(restoreDelayMs))
        snapshot.restore(to: pasteboard)
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey: CGKeyCode = 9
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown) else {
                continue
            }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }
}
