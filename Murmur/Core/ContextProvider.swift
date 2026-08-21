import AppKit

/// Identifies the app that will receive the dictated text.
@MainActor
enum ContextProvider {
    static func frontmostApp() -> (bundleId: String?, name: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }
}
