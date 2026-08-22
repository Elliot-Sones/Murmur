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

    /// Resizes for whatever the widget is currently showing.
    func layout() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = currentSize()
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 10
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func currentSize() -> NSSize {
        if ReaderController.shared.isActive {
            return NSSize(width: 460, height: 96)
        }
        switch DictationController.shared.state {
        case .recording:
            return NSSize(width: 400, height: 88)
        case .transcribing, .inserting, .preparing:
            return NSSize(width: 300, height: 56)
        case .notice:
            return NSSize(width: 420, height: 56)
        case .idle:
            return DictationController.shared.showDoneRow
                ? NSSize(width: 260, height: 48)
                : NSSize(width: 56, height: 34)
        }
    }
}
