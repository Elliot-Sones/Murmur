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
        XCTAssertEqual(store.ttsEngine, .kokoro, "built-in af_heart needs no server")
        XCTAssertEqual(store.ttsKokoroVoice, "af_heart")
        XCTAssertFalse(store.speakSelectionEnabled, "speak-on-highlight is opt-in via the pill")
        XCTAssertEqual(store.readerSpeed, 1.0, accuracy: 0.001)
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
        first.ttsEngine = .kokoroServer
        first.ttsKokoroVoice = "bm_fable"
        first.speakSelectionEnabled = true
        first.readerSpeed = 1.5

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
        XCTAssertEqual(second.ttsEngine, .kokoroServer)
        XCTAssertEqual(second.ttsKokoroVoice, "bm_fable")
        XCTAssertTrue(second.speakSelectionEnabled)
        XCTAssertEqual(second.readerSpeed, 1.5, accuracy: 0.001)
    }
}
