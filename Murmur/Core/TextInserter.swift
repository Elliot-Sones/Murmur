import AppKit

/// Pastes text into the focused app: snapshot clipboard, paste, restore clipboard.
/// `insert` returns as soon as the paste keystroke is sent; the clipboard
/// restore runs afterwards without blocking the pipeline.
@MainActor
final class TextInserter {
    private var pendingRestore: Task<Void, Never>?

    func insert(_ text: String, restoreDelayMs: Int) async {
        await pendingRestore?.value

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(capturing: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        SelectionSpeaker.shared.ignoreOwnPasteboardChange()
        KeyPoster.postCommandKey(KeyPoster.vKey)

        pendingRestore = Task {
            try? await Task.sleep(for: .milliseconds(restoreDelayMs))
            snapshot.restore(to: NSPasteboard.general)
            SelectionSpeaker.shared.ignoreOwnPasteboardChange()
        }
    }
}
