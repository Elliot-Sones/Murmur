import XCTest
@testable import Murmur

final class TtsEngineTests: XCTestCase {
    func testAllEnginesPresent() {
        XCTAssertEqual(
            TtsEngineChoice.allCases,
            [.system, .kokoro, .chatterbox, .qwen]
        )
    }

    func testDisplayNamesAreDistinctAndNonEmpty() {
        let names = TtsEngineChoice.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertFalse(names.contains(""))
    }

    func testServerModelsMapOnlyServerEngines() {
        XCTAssertNil(TtsEngineChoice.system.serverModel)
        XCTAssertNil(TtsEngineChoice.kokoro.serverModel)
        XCTAssertEqual(
            TtsEngineChoice.chatterbox.serverModel,
            "mlx-community/chatterbox-turbo-8bit"
        )
        XCTAssertEqual(
            TtsEngineChoice.qwen.serverModel,
            "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"
        )
    }
}
