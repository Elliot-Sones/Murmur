import AppKit
import SwiftUI

/// The small chat panel a dock icon opens: the job's exchange so far in a
/// scrollable transcript, and a field to answer the agent directly. Keyable
/// (unlike the pill) so typing works; Esc or clicking away collapses back to
/// the icon, the X removes the job entirely.
@MainActor
final class AgentThreadPanelController {
    static let shared = AgentThreadPanelController()
    private var panel: KeyablePanel?

    func show() {
        if panel == nil {
            let hosting = NSHostingView(rootView: AgentThreadView())
            let newPanel = KeyablePanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.contentView = hosting
            newPanel.level = .statusBar
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = true
            newPanel.hidesOnDeactivate = false
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = newPanel
        }
        guard let panel, let screen = NSScreen.main else { return }
        let size = NSSize(width: 420, height: 320)
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 64
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func resignKey() {
            super.resignKey()
            QuickChatController.shared.closeThread()
        }
        override func cancelOperation(_ sender: Any?) {
            QuickChatController.shared.closeThread()
        }
    }
}

private struct AgentThreadView: View {
    private var chat: QuickChatController { .shared }
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if let job = chat.board.expandedJob {
                thread(job)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func thread(_ job: AgentJobBoard.Job) -> some View {
        VStack(spacing: 0) {
            header(job)
            Divider().padding(.horizontal, 12)
            transcript(job)
            Divider().padding(.horizontal, 12)
            composer(job)
        }
    }

    private func header(_ job: AgentJobBoard.Job) -> some View {
        HStack(spacing: 8) {
            AgentDockIcon(job: job, reduceMotion: false)
            Text(job.agentName).font(.headline)
            if job.isWorking {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button {
                MausClient.openApp()
            } label: {
                Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open OpenMausBot")
            .accessibilityLabel("Open OpenMausBot")
            Button {
                chat.cancel(job.id)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(job.isWorking ? "Stop and remove" : "Remove")
            .accessibilityLabel("Remove \(job.agentName) from the dock")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func transcript(_ job: AgentJobBoard.Job) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(job.turns) { turn in
                        turnRow(turn)
                    }
                    if case .failed(let message) = job.phase {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .onChange(of: job.turns.count) {
                if let last = job.turns.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onAppear {
                if let last = job.turns.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func turnRow(_ turn: AgentJobBoard.Job.Turn) -> some View {
        switch turn.role {
        case .user:
            Text(turn.text)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .id(turn.id)
        case .bot:
            Text(turn.text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(turn.id)
        }
    }

    private func composer(_ job: AgentJobBoard.Job) -> some View {
        HStack(spacing: 10) {
            TextField("Answer \(job.agentName)…", text: $draft)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    chat.sendFollowUp(job.id, text: draft)
                    draft = ""
                }
                .disabled(job.botId == nil)
            Text("↩ send · esc close")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear { focused = true }
    }
}
