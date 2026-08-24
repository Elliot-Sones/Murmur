import AppKit
import SwiftUI

/// Spotlight-style floating input for the Option+Space quick chat. Unlike the
/// pill, this panel takes keyboard focus; Esc or clicking away dismisses it.
@MainActor
final class QuickChatPanelController {
    static let shared = QuickChatPanelController()
    private var panel: KeyablePanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        if panel == nil {
            let hosting = NSHostingView(rootView: QuickChatView())
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
        let size = NSSize(width: 560, height: 56)
        panel.setFrame(
            NSRect(
                origin: NSPoint(
                    x: screen.visibleFrame.midX - size.width / 2,
                    y: screen.visibleFrame.minY + screen.visibleFrame.height * 0.62
                ),
                size: size
            ),
            display: true
        )
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

/// Borderless panels refuse key status unless told otherwise, and the text
/// field is unusable without it.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        // Clicking anywhere else dismisses, Spotlight-style.
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

private struct QuickChatView: View {
    @Bindable private var chat = QuickChatController.shared
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Anyone") { chat.selectedAgentId = nil }
                Divider()
                ForEach(chat.agents) { agent in
                    Button(agent.name) { chat.selectedAgentId = agent.id }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "at")
                    Text(selectedName)
                }
                .font(.callout)
                .foregroundStyle(chat.selectedAgentId == nil ? Color.secondary : Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose which agent gets the message")

            TextField("Message an agent…", text: $chat.draft)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit { chat.send() }

            Text("↩ send · esc close")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { focused = true }
    }

    private var selectedName: String {
        chat.agents.first { $0.id == chat.selectedAgentId }?.name ?? "Anyone"
    }
}
