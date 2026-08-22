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

    /// One-line trace of every step of the AX read, for diagnosing apps
    /// where selection never surfaces.
    static func axTrace() -> String {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedErr = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        guard focusedErr == .success, let focusedRef else {
            return "focused err \(focusedErr.rawValue)"
        }
        let focused = focusedRef as! AXUIElement
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? "?"
        var selectedRef: CFTypeRef?
        let selectedErr = AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextAttribute as CFString, &selectedRef
        )
        let direct = (selectedRef as? String)?.count ?? -1
        var rangeRef: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        )
        return "role \(role) selErr \(selectedErr.rawValue) len \(direct) rangeErr \(rangeErr.rawValue)"
    }

    private static func accessibilitySelectedText() -> String? {
        guard let focused = focusedElement() else { return nil }
        if let text = selectedText(of: focused) { return text }
        // Focus often sits on a container (web area, scroll view) whose
        // selection lives on a descendant, or the app reports a stale
        // system-wide focus; retry via the frontmost app's own hierarchy.
        if let appFocused = frontmostAppFocusedElement(),
            !CFEqual(appFocused, focused),
            let text = selectedText(of: appFocused) {
            return text
        }
        return nil
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focusedRef else { return nil }
        return (focusedRef as! AXUIElement)
    }

    private static func frontmostAppFocusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focusedRef else { return nil }
        return (focusedRef as! AXUIElement)
    }

    /// Firefox, Chromium, and Electron apps build their AX tree lazily and
    /// expose nothing until an assistive client announces itself. Setting
    /// these attributes on the app element is that announcement. Once per
    /// pid; takes effect on the app's next AX query.
    private static var nudgedApps = Set<pid_t>()

    static func enableAccessibilityOfFrontmostAppIfNeeded() {
        guard let app = NSWorkspace.shared.frontmostApplication,
            !nudgedApps.contains(app.processIdentifier) else { return }
        nudgedApps.insert(app.processIdentifier)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(
            appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue
        )
        // Firefox only honors the VoiceOver-style flag. It can cause window
        // animation quirks in other apps, so keep its blast radius small.
        if app.bundleIdentifier?.hasPrefix("org.mozilla") == true {
            AXUIElementSetAttributeValue(
                appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue
            )
        }
    }

    /// Direct attribute first, then the selection range read back through the
    /// parameterized string-for-range: many text views expose only the range.
    private static func selectedText(of element: AXUIElement) -> String? {
        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selectedRef
        ) == .success, let text = selectedRef as? String, !text.isEmpty {
            return text
        }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        ) == .success, let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            return nil
        }
        let axRange = rangeRef as! AXValue
        var range = CFRange()
        guard AXValueGetValue(axRange, .cfRange, &range), range.length > 0 else { return nil }
        var stringRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &stringRef
        ) == .success, let text = stringRef as? String, !text.isEmpty else { return nil }
        return text
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
