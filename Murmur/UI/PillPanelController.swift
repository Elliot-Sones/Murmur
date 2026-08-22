import AppKit
import SwiftUI

/// Hosts the bottom-center widget: the small speak-on-highlight pill when
/// idle, the Speechify-style reader bar while reading. Never takes focus.
@MainActor
final class PillPanelController {
    static let shared = PillPanelController()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let hosting = NSHostingView(rootView: PillView())
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
            newPanel.ignoresMouseEvents = false
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = newPanel
        }
        layout()
        panel?.orderFrontRegardless()
    }

    /// Resizes for the current mode; the reader bar needs the wide frame.
    func layout() {
        guard let panel, let screen = NSScreen.main else { return }
        let reading = ReaderController.shared.isActive
        let size = reading ? NSSize(width: 440, height: 86) : NSSize(width: 56, height: 34)
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 10
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }
}
