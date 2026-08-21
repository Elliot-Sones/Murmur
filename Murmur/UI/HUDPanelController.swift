import AppKit
import SwiftUI

/// The HUD's backing panel. Subclassed because borderless panels refuse key
/// window status by default, and the review editor needs real keyboard focus.
final class ReviewHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Floating, non-activating HUD near the bottom of the screen. Never steals focus.
@MainActor
final class HUDPanelController {
    static let shared = HUDPanelController()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    /// True while the HUD owns the keyboard, which is when the review editor
    /// should swallow Return/Esc. False once the user clicks into another app.
    var reviewPanelIsKey: Bool { panel?.isKeyWindow ?? false }

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
            let newPanel = ReviewHUDPanel(
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
            // Hand the keyboard back before anything else happens; a key HUD
            // would swallow the synthetic Cmd+V meant for the target app.
            if panel.isKeyWindow { panel.orderOut(nil) }
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        panel?.orderOut(nil)
    }
}
