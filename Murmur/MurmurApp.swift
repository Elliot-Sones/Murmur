import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // isInserted is pinned true: if the status item leaves the menu bar
        // (Cmd-drag off, or overflow after a display change), macOS marks it
        // NSStatusItem VisibleCC = 0 and then terminates the app at every
        // launch as a menu-bar app with no visible item. Pinning re-inserts
        // the item instead, so the app cannot silently self-quit.
        MenuBarExtra(isInserted: .constant(true)) {
            MenuBarView()
        } label: {
            Image(systemName: menuSymbol)
        }
    }

    private var menuSymbol: String {
        switch DictationController.shared.state {
        case .recording: "waveform.badge.mic"
        case .transcribing, .inserting: "waveform.circle"
        case .notice: "exclamationmark.bubble"
        case .idle, .preparing: "waveform"
        }
    }
}
