import SwiftUI

struct SettingsView: View {
    private var settings: SettingsStore { .shared }
    private var controller: DictationController { .shared }

    var body: some View {
        Form {
            Picker("Dictation key", selection: Binding(
                get: { settings.hotkey },
                set: { settings.hotkey = $0 }
            )) {
                ForEach(HotkeyChoice.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .pickerStyle(.radioGroup)

            Toggle("Voice processing (experimental, may record silence)", isOn: Binding(
                get: { settings.voiceProcessingEnabled },
                set: { settings.voiceProcessingEnabled = $0 }
            ))

            Toggle("AI cleanup (Apple on-device model)", isOn: Binding(
                get: { settings.cleanupEnabled },
                set: { settings.cleanupEnabled = $0 }
            ))

            Stepper(
                "Clipboard restore delay: \(settings.restoreDelayMs) ms",
                value: Binding(
                    get: { settings.restoreDelayMs },
                    set: { settings.restoreDelayMs = $0 }
                ),
                in: 100...1000,
                step: 50
            )

            LabeledContent("Speech engine", value: controller.engineStatus)
            LabeledContent(
                "AI cleanup engine",
                value: FoundationModelsCleanup.isAvailable
                    ? "Apple on-device model available"
                    : "Apple Intelligence unavailable, using raw transcripts"
            )
        }
        .padding(20)
        .frame(width: 460)
    }
}
