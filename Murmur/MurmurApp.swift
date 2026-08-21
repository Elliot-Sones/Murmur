import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Murmur", systemImage: "waveform") {
            MenuBarView()
        }
        Settings {
            SettingsView()
        }
    }
}
