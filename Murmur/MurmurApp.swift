import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
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
