import SwiftUI

/// Content of the single bottom-center widget. One capsule, several faces:
/// toggle pill (idle), level meter (dictating), status row (working),
/// done row (just inserted), or the reader bar (speaking).
struct PillView: View {
    private var speaker: SelectionSpeaker { .shared }
    private var reader: ReaderController { .shared }
    private var controller: DictationController { .shared }
    private var chat: QuickChatController { .shared }
    private var requests: MausRequestMonitor { .shared }
    private var settings: SettingsStore { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True when the agent dock is the only face: it earns a slimmer capsule.
    private var showsDockOnly: Bool {
        !chat.board.isEmpty && !reader.isActive && controller.state == .idle
            && !controller.showDoneRow && requests.current == nil
    }

    private var showsPanel: Bool {
        reader.isActive || controller.state != .idle || controller.showDoneRow
            || requests.current != nil || !chat.board.isEmpty
    }

    var body: some View {
        Group {
            if showsPanel {
                // One capsule that fills the panel; faces crossfade inside
                // it so nothing appears to move.
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                    face
                        .padding(.horizontal, 18)
                        .padding(.vertical, showsDockOnly ? 5 : 10)
                }
                .padding(4)
            } else {
                togglePill
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: controller.state)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: reader.isActive)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: chat.board)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: requests.current)
    }

    @ViewBuilder
    private var face: some View {
        if reader.isActive {
            readerBar
        } else {
            switch controller.state {
            case .recording:
                recordingRow
            case .transcribing, .inserting, .preparing:
                workingRow
            case .notice(let message):
                noticeRow(message)
            case .idle:
                if controller.showDoneRow {
                    doneRow
                } else if let request = requests.current {
                    requestRow(request)
                } else if !chat.board.isEmpty {
                    agentDock
                } else {
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Agent activity dock

    /// Icon-first strip of running agents. Clicking an icon opens the job's
    /// thread panel (transcript + answer field); clicking again closes it.
    private var agentDock: some View {
        HStack(spacing: 8) {
            ForEach(chat.board.visibleJobs) { job in
                Button {
                    chat.openThread(job.id)
                } label: {
                    AgentDockIcon(job: job, reduceMotion: reduceMotion)
                }
                .buttonStyle(.plain)
                .help("\(job.agentName) — \(job.statusText)")
                .accessibilityLabel("\(job.agentName), \(job.statusText)")
                .accessibilityHint("Open thread")
            }
            if chat.board.overflowCount > 0 {
                Text("+\(chat.board.overflowCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(chat.board.overflowCount) more agents")
            }
        }
    }

    // MARK: - Agent request (question / permission)

    @ViewBuilder
    private func requestRow(_ request: PendingRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MausIcon(size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.isPermission ? "\(request.botName) · \(request.title)" : "\(request.botName) asks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !request.detail.isEmpty {
                        Text(request.detail)
                            .font(request.isPermission ? .system(.callout, design: .monospaced) : .callout)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 6)
                Button {
                    requests.dismissCurrent()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss — answer it later in OpenMausBot")
                .accessibilityLabel("Dismiss request")
            }
            requestActions(request)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func requestActions(_ request: PendingRequest) -> some View {
        HStack(spacing: 8) {
            if request.isPermission {
                Button("Allow") { requests.allow() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Deny") { requests.deny() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                ForEach(request.choices.prefix(3), id: \.self) { choice in
                    Button(choice) { requests.choose(choice) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .lineLimit(1)
                }
                if request.choices.isEmpty {
                    Button("Type an answer…") {
                        RequestAnswerPanelController.shared.show(for: request)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("Type…") {
                        RequestAnswerPanelController.shared.show(for: request)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Spacer(minLength: 4)
            Button {
                MausClient.openApp()
            } label: {
                Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open OpenMausBot")
            .accessibilityLabel("Open OpenMausBot")
        }
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
                    .lineLimit(1)
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
