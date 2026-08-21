import AppKit
import XCTest
@testable import Murmur

@MainActor
final class HUDPanelTests: XCTestCase {
    func testReviewPanelCanBecomeKey() {
        _ = NSApplication.shared
        let panel = ReviewHUDPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        XCTAssertTrue(
            panel.canBecomeKey,
            "Borderless panels refuse key status by default; the review editor needs it to receive typing, Return, and Esc"
        )
        XCTAssertFalse(
            panel.canBecomeMain,
            "The HUD must never become the main window"
        )
    }
}
