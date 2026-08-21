import AppKit
import SwiftUI

struct MenuBarView: View {
    private var permissions: PermissionsService { .shared }

    var body: some View {
        if permissions.allGranted {
            Label("Ready. Dictation lands in M1.", systemImage: "checkmark.circle")
        } else {
            Button("Finish Setup…") { OnboardingWindowController.shared.show() }
        }
        Divider()
        SettingsLink {
            Text("Settings…")
        }
        Divider()
        Button("Quit Murmur") { NSApp.terminate(nil) }
    }
}
