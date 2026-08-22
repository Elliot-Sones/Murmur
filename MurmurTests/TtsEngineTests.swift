import XCTest
@testable import Murmur

final class TtsEngineTests: XCTestCase {
    func testExactlyTwoKokoroProviders() {
        XCTAssertEqual(
            TtsEngineChoice.allCases,
            [.kokoro, .kokoroServer],
            "Elliot kept only the two Kokoro providers"
        )
    }

    func testDisplayNamesAreDistinctAndNonEmpty() {
        let names = TtsEngineChoice.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertFalse(names.contains(""))
    }

    func testServerModelsMapOnlyServerEngines() {
        XCTAssertNil(TtsEngineChoice.kokoro.serverModel, "af_heart runs inside the app")
        XCTAssertEqual(
            TtsEngineChoice.kokoroServer.serverModel,
            "mlx-community/Kokoro-82M-bf16"
        )
    }

    func testKokoroVoiceListCoversTheEnglishSet() {
        XCTAssertTrue(TtsEngineChoice.kokoroVoices.contains("af_heart"))
        XCTAssertTrue(TtsEngineChoice.kokoroVoices.contains("bm_fable"))
        XCTAssertGreaterThanOrEqual(TtsEngineChoice.kokoroVoices.count, 12)
    }
}
