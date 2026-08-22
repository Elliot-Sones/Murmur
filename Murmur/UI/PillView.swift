import SwiftUI

/// Bottom-center widget. Idle: a small waveform pill (same icon family as
/// the dictation HUD) that toggles speak-on-highlight. Reading: a
/// Speechify-style player bar with skip, play/pause, speed, and progress.
struct PillView: View {
    private var speaker: SelectionSpeaker { .shared }
    private var reader: ReaderController { .shared }

    var body: some View {
        Group {
            if reader.isActive {
                readerBar
            } else {
                togglePill
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var togglePill: some View {
        Button {
            speaker.enabled.toggle()
        } label: {
            Image(systemName: "waveform")
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
    }

    private var readerBar: some View {
        VStack(spacing: 5) {
            if let errorMessage = reader.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if let sentence = reader.currentSentence {
                Text(sentence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 14) {
                Button { reader.skipBack() } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.plain)
                .help("Previous sentence")
                .accessibilityLabel("Previous sentence")

                Button { reader.playPause() } label: {
                    Image(systemName: reader.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(reader.isPlaying ? "Pause" : "Play")
                .accessibilityLabel(reader.isPlaying ? "Pause" : "Play")

                Button { reader.skipForward() } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
                .help("Next sentence")
                .accessibilityLabel("Next sentence")

                Button { reader.cycleSpeed() } label: {
                    Text(ReaderSpeed.label(for: reader.speed))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 38, height: 20)
                        .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Playback speed")
                .accessibilityLabel("Playback speed \(ReaderSpeed.label(for: reader.speed))")

                Text("\(reader.index + 1)/\(reader.sentences.count)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)

                Button { reader.stop() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Stop reading")
                .accessibilityLabel("Stop reading")
            }

            ProgressView(value: reader.progress)
                .progressViewStyle(.linear)
                .controlSize(.small)
                .tint(Color.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
