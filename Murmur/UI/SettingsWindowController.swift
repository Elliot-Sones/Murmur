import AppKit
import SwiftUI

/// Owns the Settings window directly. The SwiftUI `Settings` scene dismisses
/// on deactivate in accessory (menu-bar-only) apps; a plain NSWindow stays
/// open until the user closes it.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Murmur Settings"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setFrameAutosaveName("MurmurSettingsWindow")
            if !newWindow.setFrameUsingName("MurmurSettingsWindow") {
                newWindow.center()
            }
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
