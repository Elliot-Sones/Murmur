import AppKit
import SwiftUI

struct MenuBarView: View {
    private var permissions: PermissionsService { .shared }
    private var controller: DictationController { .shared }
    private var settings: SettingsStore { .shared }

    var body: some View {
        Text(statusLine)
        if !permissions.allGranted {
            Button("Finish Setup…") { OnboardingWindowController.shared.show() }
        }
        if let stats = controller.lastRun {
            Divider()
            Text(stats.audioSummary)
            Text(stats.stageSummary)
            Text("Cleanup: \(stats.engine)")
        }
        Divider()
        Toggle("AI Cleanup", isOn: Binding(
            get: { settings.cleanupEnabled },
            set: { settings.cleanupEnabled = $0 }
        ))
        if controller.lastRecord != nil {
            Button("Speak Last Dictation") { controller.speakLastRecord() }
        }
        Divider()
        Button("Settings…") { SettingsWindowController.shared.show() }
        Divider()
        Button("Quit Murmur") { NSApp.terminate(nil) }
    }

    private var statusLine: String {
        switch controller.state {
        case .idle:
            let hotkey = settings.hotkey.shortName
            if let latency = controller.lastLatencyMs {
                return "Ready. Hold \(hotkey) to dictate. Last: \(latency) ms"
            }
            return "Ready. Hold \(hotkey) to dictate."
        case .preparing(let message):
            return message
        case .recording:
            return "Listening…"
        case .transcribing:
            return "Transcribing…"
        case .inserting:
            return "Inserting…"
        case .notice(let message):
            return message
        }
    }
}
