import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.elliot.Murmur", category: "app")
    private let launchedAt = Date()
    /// Set by the menu's Quit item so a real quit is always honored.
    var quitRequested = false

    /// A status item that was dragged out of the menu bar (or squeezed out
    /// by overflow) leaves NSStatusItem VisibleCC = 0 behind, and the scene
    /// system then delivers a terminate to a menu-bar-only app moments after
    /// every launch: the app looks like it "opens and instantly closes".
    /// Refuse terminates that arrive in that launch window and repair the
    /// visibility flag; user quits, logout, and shutdown are unaffected
    /// (quitRequested covers the menu item; the window is only 10 s).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !quitRequested, Date().timeIntervalSince(launchedAt) < 10 {
            log.error("refused terminate within 10 s of launch; repairing status item visibility")
            UserDefaults.standard.set(true, forKey: "NSStatusItem VisibleCC Item-0")
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.notice("Murmur launched")
        let permissions = PermissionsService.shared
        permissions.refresh()
        if !permissions.allGranted {
            OnboardingWindowController.shared.show()
        }
        DictationController.shared.prepareEngines()
        HotkeyService.shared.ensureRunning()
        PillPanelController.shared.show()
        SelectionSpeaker.shared.syncWithSettings()
    }

    /// Opening the app while it is already running surfaces the status window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        log.notice("Reopen requested; showing status window")
        OnboardingWindowController.shared.show()
        return true
    }
}
