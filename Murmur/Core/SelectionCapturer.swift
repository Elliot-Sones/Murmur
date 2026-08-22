import AppKit
import ApplicationServices

/// Reads the currently selected text in the focused app.
/// Accessibility first (non-destructive); synthetic Cmd+C as fallback for
/// apps that do not expose selection through AX.
@MainActor
enum SelectionCapturer {
    static func capture() async -> String? {
        if let viaAX = accessibilitySelectedText(), !viaAX.isEmpty {
            return viaAX
        }
        return await pasteboardCopy()
    }

    /// AX-only read, safe to poll: never posts keys or touches the pasteboard.
    static func axSelectedText() -> String? {
        accessibilitySelectedText()
    }

    private static func accessibilitySelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focusedRef else { return nil }
        let focused = focusedRef as! AXUIElement

        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextAttribute as CFString, &selectedRef
        ) == .success else { return nil }
        return selectedRef as? String
    }

    private static func pasteboardCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(capturing: pasteboard)
        let changeCountBefore = pasteboard.changeCount

        KeyPoster.postCommandKey(KeyPoster.cKey)
        try? await Task.sleep(for: .milliseconds(150))

        defer { snapshot.restore(to: pasteboard) }
        guard pasteboard.changeCount != changeCountBefore else { return nil }
        return pasteboard.string(forType: .string)
    }
}
