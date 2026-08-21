import AppKit
import XCTest
@testable import Murmur

final class PasteboardSnapshotTests: XCTestCase {
    private let customType = NSPasteboard.PasteboardType("com.elliot.murmur.test-payload")

    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("murmur-test-\(UUID().uuidString)"))
    }

    func testRestoreBringsBackStringAndCustomData() {
        let pasteboard = scratchPasteboard()
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("original", forType: .string)
        item.setData(payload, forType: customType)
        pasteboard.writeObjects([item])

        let snapshot = PasteboardSnapshot(capturing: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("murmur dictation output", forType: .string)
        snapshot.restore(to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(pasteboard.data(forType: customType), payload)
    }

    func testRestoringEmptySnapshotClearsPasteboard() {
        let pasteboard = scratchPasteboard()
        pasteboard.clearContents()

        let snapshot = PasteboardSnapshot(capturing: pasteboard)
        pasteboard.setString("temporary", forType: .string)
        snapshot.restore(to: pasteboard)

        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
