import AppKit
import SwiftUI

/// A small focused input for typing a free-text answer to a bot's question,
/// opened from the pill's "Type…" button. The pill itself never takes focus,
/// so the write path needs its own key panel — the same borderless-but-keyable
/// trick the Option+Space quick chat uses.
@MainActor
final class RequestAnswerPanelController {
    static let shared = RequestAnswerPanelController()
    private var panel: KeyablePanel?

    func show(for request: PendingRequest) {
        if panel == nil {
            let hosting = NSHostingView(rootView: RequestAnswerView())
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
        prompt = request.detail.isEmpty ? "Type your answer" : request.detail
        draft = ""
        let size = NSSize(width: 560, height: 92)
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + screen.visibleFrame.height * 0.62
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // Bound into the SwiftUI view; simple shared state keeps the panel light.
    fileprivate var prompt = ""
    fileprivate var draft = ""

    fileprivate func submit() {
        MausRequestMonitor.shared.submitTyped(draft)
        hide()
    }

    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func resignKey() {
            super.resignKey()
            orderOut(nil)
        }
        override func cancelOperation(_ sender: Any?) {
            orderOut(nil)
        }
    }
}

private struct RequestAnswerView: View {
    private let controller = RequestAnswerPanelController.shared
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(controller.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 10) {
                MausIcon(size: 18)
                TextField("Type your answer…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit {
                        controller.draft = draft
                        controller.submit()
                    }
                Text("↩ send · esc close")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: draft) { controller.draft = draft }
        .onAppear { focused = true }
    }
}
