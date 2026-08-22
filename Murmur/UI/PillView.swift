import SwiftUI

/// Content of the single bottom-center widget. One capsule, several faces:
/// toggle pill (idle), level meter (dictating), status row (working),
/// done row (just inserted), or the reader bar (speaking).
struct PillView: View {
    private var speaker: SelectionSpeaker { .shared }
    private var reader: ReaderController { .shared }
    private var controller: DictationController { .shared }
    private var settings: SettingsStore { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reader.isActive {
                readerBar.padding(.horizontal, 14).padding(.vertical, 8).background(capsule)
            } else {
                switch controller.state {
                case .recording:
                    recordingRow.padding(.horizontal, 16).padding(.vertical, 10).background(capsule)
                case .transcribing, .inserting, .preparing:
                    workingRow.padding(.horizontal, 16).padding(.vertical, 10).background(capsule)
                case .notice(let message):
                    noticeRow(message).padding(.horizontal, 16).padding(.vertical, 10).background(capsule)
                case .idle:
                    if controller.showDoneRow {
                        doneRow.padding(.horizontal, 14).padding(.vertical, 8).background(capsule)
                    } else {
                        togglePill
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: controller.state)
    }

    private var capsule: some View {
        RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
    }

    // MARK: - Idle toggle

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
                ? "Speaking highlighted text. Click to turn off. Tap \(settings.hotkey.shortName) to dictate."
                : "Click to speak highlighted text. Tap \(settings.hotkey.shortName) to dictate."
        )
        .accessibilityLabel("Speak highlighted text")
        .accessibilityValue(speaker.enabled ? "on" : "off")
    }

    // MARK: - Dictation faces

    private var recordingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                LevelMeter(level: controller.audioLevel, reduceMotion: reduceMotion)
                Text(controller.mode == .command ? "Command: speak an instruction" : "Listening")
                    .font(.callout)
                Text("Tap \(controller.mode == .command ? settings.commandHotkey.shortName : settings.hotkey.shortName) to finish · Esc cancels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !controller.previewText.isEmpty {
                Text(controller.previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .transition(.opacity)
            }
        }
    }

    private var workingRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            switch controller.state {
            case .transcribing:
                Text(controller.mode == .command ? "Rewriting" : "Transcribing").font(.callout)
            case .inserting:
                Text("Inserting").font(.callout)
            case .preparing(let message):
                Text(message).font(.callout)
            default:
                EmptyView()
            }
        }
    }

    private func noticeRow(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            Text(message).font(.callout)
        }
    }

    private var doneRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if let latency = controller.lastLatencyMs {
                Text("Done in \(latency) ms")
                    .font(.callout)
                    .monospacedDigit()
            } else {
                Text("Done").font(.callout)
            }
            if let record = controller.lastRecord {
                Spacer(minLength: 8)
                Button {
                    controller.flagLastRecord()
                } label: {
                    Image(systemName: record.vote == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .foregroundStyle(record.vote == -1 ? .red : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Flag this dictation as wrong")
                .accessibilityLabel("Flag last dictation as wrong")
            }
        }
    }

    // MARK: - Reader bar

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
    }
}

private struct LevelMeter: View {
    let level: Float
    let reduceMotion: Bool
    private let barCount = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.tint)
                    .frame(width: 3, height: barHeight(index))
            }
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: level)
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let threshold = Float(index + 1) / Float(barCount + 1)
        let active = level >= threshold
        return active ? CGFloat(8 + index * 4) : 4
    }
}
