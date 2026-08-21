import SwiftUI

struct HUDView: View {
    private var controller: DictationController { .shared }

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
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .recording:
            LevelMeter(level: controller.audioLevel)
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
            } else {
                Text("Done")
            }
        case .preparing(let message):
            ProgressView().controlSize(.small)
            Text(message)
        }
    }
}

private struct LevelMeter: View {
    let level: Float
    private let barCount = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.tint)
                    .frame(width: 3, height: barHeight(index))
            }
        }
        .animation(.linear(duration: 0.08), value: level)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let threshold = Float(index + 1) / Float(barCount + 1)
        let active = level >= threshold
        return active ? CGFloat(8 + index * 4) : 4
    }
}
