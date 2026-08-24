import AppKit
import SwiftUI

/// Spotlight-style floating input for the Option+Space quick chat. Unlike the
/// pill, this panel takes keyboard focus; Esc or clicking away dismisses it.
@MainActor
final class QuickChatPanelController {
    static let shared = QuickChatPanelController()
    static let baseHeight: CGFloat = 56
    private var panel: KeyablePanel?
    /// Fixed top edge; the mention dropdown grows the panel downward from it.
    private var topY: CGFloat = 0

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
        let size = NSSize(width: 560, height: Self.baseHeight)
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + screen.visibleFrame.height * 0.62
        )
        topY = origin.y + size.height
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// The content view drives this as the mention dropdown appears and hides.
    func setHeight(_ height: CGFloat) {
        guard let panel, panel.isVisible else { return }
        var frame = panel.frame
        guard frame.height != height else { return }
        frame.origin.y = topY - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
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
    @State private var highlighted = 0

    private static let rowHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputRow
                .frame(height: QuickChatPanelController.baseHeight - 8)
            if !suggestions.isEmpty {
                Divider().padding(.horizontal, 12)
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, agent in
                        suggestionRow(agent, isHighlighted: index == highlighted)
                            .onTapGesture { accept(agent) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onAppear {
            focused = true
            highlighted = 0
        }
        .onChange(of: chat.draft) {
            highlighted = 0
            resize()
        }
        .onChange(of: chat.agents) { resize() }
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Anyone") { chat.selectedAgentId = nil }
                Divider()
                ForEach(chat.agents) { agent in
                    Button(agent.name) { chat.selectedAgentId = agent.id }
                }
            } label: {
                HStack(spacing: 6) {
                    MausIcon(size: 18)
                    Text(selectedName)
                }
                .font(.callout)
                .foregroundStyle(chat.selectedAgentId == nil ? Color.secondary : Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose which agent gets the message")

            TextField("Message an agent… type @ to pick one", text: $chat.draft)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onSubmit {
                    if let agent = suggestions[safe: highlighted] {
                        accept(agent)
                    } else {
                        chat.send()
                    }
                }
                .onKeyPress(.downArrow) { moveHighlight(1) }
                .onKeyPress(.upArrow) { moveHighlight(-1) }
                .onKeyPress(.tab) {
                    guard let agent = suggestions[safe: highlighted] else { return .ignored }
                    accept(agent)
                    return .handled
                }

            Text("↩ send · esc close")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
    }

    private func suggestionRow(_ agent: MausBot, isHighlighted: Bool) -> some View {
        HStack {
            Text(agent.name).font(.callout)
            Spacer()
            if isHighlighted {
                Text("↩")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Self.rowHeight)
        .background(
            isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Mention parsing

    /// The trailing "@query" token being typed, if any: an @ at the start of
    /// the draft or after whitespace, with no space after it.
    private var mentionRange: Range<String.Index>? {
        guard let atIndex = chat.draft.lastIndex(of: "@") else { return nil }
        let after = chat.draft[chat.draft.index(after: atIndex)...]
        guard !after.contains(where: \.isWhitespace) else { return nil }
        if atIndex != chat.draft.startIndex {
            guard chat.draft[chat.draft.index(before: atIndex)].isWhitespace else { return nil }
        }
        return atIndex..<chat.draft.endIndex
    }

    private var suggestions: [MausBot] {
        guard let mentionRange else { return [] }
        let query = chat.draft[chat.draft.index(after: mentionRange.lowerBound)...].lowercased()
        guard !query.isEmpty else { return chat.agents }
        let prefixed = chat.agents.filter { $0.name.lowercased().hasPrefix(query) }
        let contained = chat.agents.filter {
            !$0.name.lowercased().hasPrefix(query) && $0.name.lowercased().contains(query)
        }
        return prefixed + contained
    }

    private func accept(_ agent: MausBot) {
        chat.selectedAgentId = agent.id
        if let mentionRange {
            chat.draft.removeSubrange(mentionRange)
        }
        focused = true
    }

    private func moveHighlight(_ delta: Int) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        highlighted = (highlighted + delta + suggestions.count) % suggestions.count
        return .handled
    }

    private func resize() {
        let rows = suggestions.count
        let height = QuickChatPanelController.baseHeight
            + (rows == 0 ? 0 : CGFloat(rows) * Self.rowHeight + 13)
        QuickChatPanelController.shared.setHeight(height)
    }

    private var selectedName: String {
        chat.agents.first { $0.id == chat.selectedAgentId }?.name ?? "Anyone"
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
