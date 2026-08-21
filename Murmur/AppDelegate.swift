import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.elliot.Murmur", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.notice("Murmur launched")
        let permissions = PermissionsService.shared
        permissions.refresh()
        if !permissions.allGranted {
            OnboardingWindowController.shared.show()
        }
        DictationController.shared.prepareEngines()
        HotkeyService.shared.ensureRunning()
    }

    /// Opening the app while it is already running surfaces the status window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        log.notice("Reopen requested; showing status window")
        OnboardingWindowController.shared.show()
        return true
    }
}
