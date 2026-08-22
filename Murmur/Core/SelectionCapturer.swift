import AppKit
import ApplicationServices
import os

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

    private static let log = Logger(subsystem: "com.elliot.Murmur", category: "selection")

    private static func pasteboardCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(capturing: pasteboard)
        let changeCountBefore = pasteboard.changeCount

        // The app's own Edit > Copy menu item, pressed through AX, is immune
        // to whatever modifier keys are still physically held.
        var method = "menu"
        if !pressEditCopyMenuItem() {
            method = "keystroke"
            // Without the menu item, fall back to synthetic Cmd+C, which
            // requires the hotkey's own modifiers to be up first.
            await KeyPoster.waitForModifierRelease()
            KeyPoster.postCommandKey(KeyPoster.cKey)
        }
        // Poll rather than one fixed sleep; some apps take a while to
        // service a copy.
        let deadline = ContinuousClock.now + .milliseconds(1200)
        while pasteboard.changeCount == changeCountBefore, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }

        defer { snapshot.restore(to: pasteboard) }
        let changed = pasteboard.changeCount != changeCountBefore
        log.notice("copy fallback via \(method, privacy: .public): pasteboard \(changed ? "changed" : "unchanged", privacy: .public)")
        guard changed else { return nil }
        return pasteboard.string(forType: .string)
    }

    /// Finds Edit > Copy in the frontmost app's menu bar and presses it.
    private static func pressEditCopyMenuItem() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXMenuBarAttribute as CFString, &menuBarRef
        ) == .success, let menuBarRef else { return false }
        let menuBar = menuBarRef as! AXUIElement
        guard let editMenu = children(of: menuBar).first(where: { title(of: $0) == "Edit" })
        else { return false }
        // The menu's items live one level down, inside the AXMenu child.
        for container in children(of: editMenu) {
            if let copyItem = children(of: container).first(where: { title(of: $0) == "Copy" }) {
                return AXUIElementPerformAction(copyItem, kAXPressAction as CFString) == .success
            }
        }
        return false
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRef
        ) == .success, let array = childrenRef as? [AXUIElement] else { return [] }
        return array
    }

    private static func title(of element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXTitleAttribute as CFString, &titleRef
        ) == .success else { return nil }
        return titleRef as? String
    }
}
