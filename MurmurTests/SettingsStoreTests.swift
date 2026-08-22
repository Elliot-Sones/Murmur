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
        XCTAssertEqual(store.cleanupEngine, .apple)
        XCTAssertEqual(store.ollamaModel, "")
        XCTAssertTrue(store.soundCuesEnabled)
        XCTAssertEqual(store.commandHotkey, .rightOption)
        XCTAssertEqual(store.ttsEngine, .system, "read-back must work with zero downloads by default")
        XCTAssertEqual(store.ttsKokoroVoice, "af_heart")
        XCTAssertEqual(store.ttsQwenVoice, "Vivian")
    }

    @MainActor
    func testChoosingControlOptionDictationMovesCommandOffRightOption() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertEqual(store.commandHotkey, .rightOption)
        store.hotkey = .controlOption
        XCTAssertEqual(
            store.commandHotkey, .controlO,
            "right option is part of the dictation chord and must be vacated"
        )
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
        first.cleanupEngine = .ollama
        first.ollamaModel = "gemma4:latest"
        first.soundCuesEnabled = false
        first.commandHotkey = .controlO
        first.ttsEngine = .chatterbox
        first.ttsKokoroVoice = "bm_george"
        first.ttsQwenVoice = "Ethan"

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.hotkey, .rightCommand)
        XCTAssertFalse(second.voiceProcessingEnabled)
        XCTAssertFalse(second.cleanupEnabled)
        XCTAssertFalse(second.streamingPreviewEnabled)
        XCTAssertEqual(second.restoreDelayMs, 400)
        XCTAssertEqual(second.cleanupEngine, .ollama)
        XCTAssertEqual(second.ollamaModel, "gemma4:latest")
        XCTAssertFalse(second.soundCuesEnabled)
        XCTAssertEqual(second.commandHotkey, .controlO)
        XCTAssertEqual(second.ttsEngine, .chatterbox)
        XCTAssertEqual(second.ttsKokoroVoice, "bm_george")
        XCTAssertEqual(second.ttsQwenVoice, "Ethan")
    }
}
