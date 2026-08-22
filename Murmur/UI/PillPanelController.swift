import AppKit
import SwiftUI

/// The app's single floating widget, bottom-center: a small toggle pill when
/// idle, and the same capsule grown into a level meter while dictating, a
/// status row while working, or the reader bar while speaking. Never takes
/// focus.
@MainActor
final class PillPanelController {
    static let shared = PillPanelController()
    private var panel: NSPanel?
    private var lingerTask: Task<Void, Never>?

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

    /// Dictation drives the widget through here.
    func stateChanged(_ state: DictationController.State) {
        lingerTask?.cancel()
        if case .idle = state, DictationController.shared.showDoneRow {
            // Keep the done row (latency + flag button) reachable briefly.
            lingerTask = Task {
                try? await Task.sleep(for: .milliseconds(3000))
                guard !Task.isCancelled else { return }
                DictationController.shared.expireDoneRow()
                self.layout()
            }
        }
        layout()
    }

    /// Resizes for whatever the widget is currently showing. Every active
    /// face shares one size so faces crossfade inside a still capsule; the
    /// only geometry changes are pill-to-panel and back, animated.
    func layout() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = currentSize()
        guard panel.frame.size != size else {
            panel.orderFrontRegardless()
            return
        }
        let frame = NSRect(
            origin: NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.minY + 10
            ),
            size: size
        )
        panel.setFrame(frame, display: true, animate: true)
        panel.orderFrontRegardless()
    }

    private func currentSize() -> NSSize {
        let active = ReaderController.shared.isActive
            || DictationController.shared.state != .idle
            || DictationController.shared.showDoneRow
        return active ? NSSize(width: 460, height: 96) : NSSize(width: 56, height: 34)
    }
}
