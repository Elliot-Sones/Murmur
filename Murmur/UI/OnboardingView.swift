import SwiftUI

struct OnboardingView: View {
    private var permissions: PermissionsService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Murmur")
                    .font(.title.bold())
                Text("Hold Fn anywhere, speak, release. Your words appear at the cursor. Everything runs on this Mac.")
                    .foregroundStyle(.secondary)
            }

            stepRow(
                title: "Microphone",
                detail: "Records your voice only while you hold the dictation key.",
                state: permissions.snapshot.microphone
            ) {
                if permissions.snapshot.microphone == .notDetermined {
                    Button("Allow…") { permissions.requestMicrophone() }
                } else {
                    Button("Open Settings") { SystemSettingsPane.microphone.open() }
                }
            }

            stepRow(
                title: "Accessibility",
                detail: "Lets Murmur paste text into the focused app.",
                state: permissions.snapshot.accessibility
            ) {
                Button("Open Settings") {
                    permissions.promptAccessibility()
                    SystemSettingsPane.accessibility.open()
                }
            }

            stepRow(
                title: "Input Monitoring",
                detail: "Lets Murmur detect the Fn key in any app.",
                state: permissions.snapshot.inputMonitoring
            ) {
                Button("Open Settings") {
                    permissions.requestInputMonitoring()
                    SystemSettingsPane.inputMonitoring.open()
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free the Fn key")
                        .font(.headline)
                    Text("Set Keyboard > \"Press 🌐 key\" to \"Do Nothing\" so Murmur can own it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Keyboard Settings") { SystemSettingsPane.keyboard.open() }
            }

            Divider()

            if permissions.allGranted {
                Label("All set. Dictation arrives with the next milestone.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Grant all three permissions above. This window updates automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 500)
        .task { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }

    @ViewBuilder
    private func stepRow(
        title: String,
        detail: String,
        state: PermissionState,
        @ViewBuilder action: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.symbolName)
                .foregroundStyle(state == .granted ? .green : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state != .granted {
                action()
            }
        }
    }
}
