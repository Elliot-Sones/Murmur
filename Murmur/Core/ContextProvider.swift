import AppKit
import ApplicationServices

/// Identifies the app and window that will receive the dictated text.
@MainActor
enum ContextProvider {
    struct Target {
        var bundleId: String?
        var name: String?
        var windowTitle: String?
    }

    static func frontmostTarget() -> Target {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return Target()
        }
        return Target(
            bundleId: app.bundleIdentifier,
            name: app.localizedName,
            windowTitle: focusedWindowTitle(pid: app.processIdentifier)
        )
    }

    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let axApp = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &windowRef
        ) == .success, let windowRef else { return nil }
        let window = windowRef as! AXUIElement

        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window, kAXTitleAttribute as CFString, &titleRef
        ) == .success else { return nil }
        return titleRef as? String
    }
}
