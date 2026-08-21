import AppKit
import SwiftUI

/// Owns the Settings window directly. The SwiftUI `Settings` scene dismisses
/// on deactivate in accessory (menu-bar-only) apps; a plain NSWindow stays
/// open until the user closes it.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(tab: String? = nil) {
        if let tab {
            UserDefaults.standard.set(tab, forKey: "settingsSelectedTab")
        }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Murmur Settings"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            // Windows created during menu-bar tracking inherit an elevated
            // level and float over other apps; pin to normal.
            newWindow.level = .normal
            // Come to the user's current Space instead of yanking them to
            // the Space where the window last lived.
            newWindow.collectionBehavior = [.moveToActiveSpace]
            newWindow.setFrameAutosaveName("MurmurSettingsWindow")
            if !newWindow.setFrameUsingName("MurmurSettingsWindow") {
                newWindow.center()
            }
            window = newWindow
        }
        window?.level = .normal
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
