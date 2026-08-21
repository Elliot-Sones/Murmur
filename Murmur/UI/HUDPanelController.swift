import AppKit
import SwiftUI

/// Floating, non-activating HUD near the bottom of the screen. Never steals focus.
@MainActor
final class HUDPanelController {
    static let shared = HUDPanelController()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func stateChanged(_ state: DictationController.State) {
        switch state {
        case .recording, .transcribing, .inserting, .notice:
            hideTask?.cancel()
            show()
        case .preparing:
            break
        case .idle:
            hideTask?.cancel()
            hideTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                self.hide()
            }
        }
    }

    private func show() {
        if panel == nil {
            let hosting = NSHostingView(rootView: HUDView())
            let newPanel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.contentView = hosting
            newPanel.level = .statusBar
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = false
            newPanel.ignoresMouseEvents = true
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = newPanel
        }
        guard let panel, let screen = NSScreen.main else { return }
        let size = NSSize(width: 360, height: 96)
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 96
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }
}
