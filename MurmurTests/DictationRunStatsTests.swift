import XCTest
@testable import Murmur

final class DictationRunStatsTests: XCTestCase {
    private let stats = DictationRunStats(
        audioMs: 6900,
        transcribeMs: 93,
        cleanupMs: 337,
        pasteMs: 11,
        characters: 61,
        engine: "Apple on-device"
    )

    func testTotalSumsStagesAfterRelease() {
        XCTAssertEqual(stats.totalMs, 441)
    }

    func testAudioSummary() {
        XCTAssertEqual(stats.audioSummary, "6.9 s audio → 61 chars in 441 ms")
    }

    func testStageSummary() {
        XCTAssertEqual(stats.stageSummary, "ASR 93 ms · Cleanup 337 ms · Paste 11 ms")
    }
}
