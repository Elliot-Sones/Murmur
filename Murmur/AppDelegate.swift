import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let permissions = PermissionsService.shared
        permissions.refresh()
        if !permissions.allGranted {
            OnboardingWindowController.shared.show()
        }
        DictationController.shared.prepareEngines()
        HotkeyService.shared.ensureRunning()
    }
}
