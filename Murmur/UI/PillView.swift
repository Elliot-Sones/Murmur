import SwiftUI

/// The always-there toggle at the bottom of the screen: click to turn
/// speak-on-highlight on or off.
struct PillView: View {
    private var speaker: SelectionSpeaker { .shared }

    var body: some View {
        Button {
            speaker.enabled.toggle()
        } label: {
            Image(systemName: speaker.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(speaker.enabled ? Color.accentColor : Color.secondary)
                .frame(width: 44, height: 26)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        speaker.enabled ? Color.accentColor.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .help(
            speaker.enabled
                ? "Speaking highlighted text. Click to turn off."
                : "Click to speak any text you highlight."
        )
        .accessibilityLabel("Speak highlighted text")
        .accessibilityValue(speaker.enabled ? "on" : "off")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
