import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Welcome to Murmur"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            // Windows created during menu-bar tracking inherit an elevated
            // level and float over other apps; pin to normal.
            newWindow.level = .normal
            newWindow.center()
            window = newWindow
        }
        window?.level = .normal
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
