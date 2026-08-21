import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController {
    static let shared = HistoryWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: HistoryView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Dictation History"
            newWindow.styleMask = [.titled, .closable, .resizable]
            newWindow.setContentSize(NSSize(width: 640, height: 480))
            newWindow.isReleasedWhenClosed = false
            newWindow.setFrameAutosaveName("MurmurHistoryWindow")
            if !newWindow.setFrameUsingName("MurmurHistoryWindow") {
                newWindow.center()
            }
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
