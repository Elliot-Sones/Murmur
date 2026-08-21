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
            show(interactive: false, key: false, tall: false)
        case .reviewing:
            hideTask?.cancel()
            show(interactive: true, key: true, tall: true)
        case .preparing:
            break
        case .idle:
            hideTask?.cancel()
            // Linger so the thumbs-down stays reachable for a moment.
            show(interactive: true, key: false, tall: false)
            hideTask = Task {
                try? await Task.sleep(for: .milliseconds(3000))
                guard !Task.isCancelled else { return }
                self.hide()
            }
        }
    }

    private func show(interactive: Bool, key: Bool, tall: Bool) {
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
        panel.ignoresMouseEvents = !interactive
        let size = tall ? NSSize(width: 460, height: 150) : NSSize(width: 360, height: 96)
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 96
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if key {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        panel?.orderOut(nil)
    }
}
