import SwiftUI

struct HUDView: View {
    private var controller: DictationController { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                content
            }
            if case .recording = controller.state, !controller.previewText.isEmpty {
                Text(controller.previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .transition(.opacity)
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: controller.state
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: controller.previewText
        )
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .recording:
            LevelMeter(level: controller.audioLevel, reduceMotion: reduceMotion)
            Text(controller.mode == .command ? "Command: speak an instruction" : "Listening")
            Text("Esc cancels")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .transcribing:
            ProgressView().controlSize(.small)
            Text(controller.mode == .command ? "Rewriting" : "Transcribing")
        case .inserting:
            Image(systemName: "text.cursor")
            Text("Inserting")
        case .notice(let message):
            Image(systemName: "exclamationmark.triangle")
            Text(message)
        case .idle:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if let latency = controller.lastLatencyMs {
                Text("Done in \(latency) ms")
                    .monospacedDigit()
            } else {
                Text("Done")
            }
            if let record = controller.lastRecord {
                Spacer(minLength: 12)
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
        case .preparing(let message):
            ProgressView().controlSize(.small)
            Text(message)
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
