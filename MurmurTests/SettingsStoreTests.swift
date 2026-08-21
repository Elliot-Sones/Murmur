import XCTest
@testable import Murmur

final class SettingsStoreTests: XCTestCase {
    private var suiteName = ""

    override func tearDown() {
        if !suiteName.isEmpty {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    private func freshDefaults() -> UserDefaults {
        suiteName = "murmur-tests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @MainActor
    func testDefaults() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertEqual(store.hotkey, .fn)
        XCTAssertFalse(
            store.voiceProcessingEnabled,
            "voice processing must default off: without a full-duplex audio path it records silence"
        )
        XCTAssertTrue(store.cleanupEnabled)
        XCTAssertTrue(store.streamingPreviewEnabled)
        XCTAssertEqual(store.restoreDelayMs, 250)
    }

    @MainActor
    func testPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let first = SettingsStore(defaults: defaults)
        first.hotkey = .rightCommand
        first.voiceProcessingEnabled = false
        first.cleanupEnabled = false
        first.streamingPreviewEnabled = false
        first.restoreDelayMs = 400

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.hotkey, .rightCommand)
        XCTAssertFalse(second.voiceProcessingEnabled)
        XCTAssertFalse(second.cleanupEnabled)
        XCTAssertFalse(second.streamingPreviewEnabled)
        XCTAssertEqual(second.restoreDelayMs, 400)
    }
}
