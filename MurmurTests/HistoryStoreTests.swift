import XCTest
@testable import Murmur

final class HistoryStoreTests: XCTestCase {
    @MainActor
    private func makeStore() throws -> HistoryStore {
        try HistoryStore(inMemory: true)
    }

    @MainActor
    private func record(
        text: String, raw: String = "", daysAgo: Double = 0, app: String? = nil
    ) -> DictationRecord {
        DictationRecord(
            date: Date(timeIntervalSinceNow: -daysAgo * 86_400),
            appBundleId: app,
            appName: app,
            rawTranscript: raw.isEmpty ? text : raw,
            cleanedText: text,
            audioMs: 3000,
            totalMs: 450,
            engine: "Apple on-device model"
        )
    }

    @MainActor
    func testAddThenFetchNewestFirst() throws {
        let store = try makeStore()
        store.add(record(text: "older entry", daysAgo: 2))
        store.add(record(text: "newest entry", daysAgo: 0))
        store.add(record(text: "middle entry", daysAgo: 1))

        let all = store.records(matching: "")
        XCTAssertEqual(all.map(\.cleanedText), ["newest entry", "middle entry", "older entry"])
    }

    @MainActor
    func testSearchMatchesCleanedAndRawText() throws {
        let store = try makeStore()
        store.add(record(text: "send the invoice tomorrow"))
        store.add(record(text: "totally unrelated", raw: "um invoice raw only"))
        store.add(record(text: "no match here"))

        XCTAssertEqual(store.records(matching: "invoice").count, 2)
        XCTAssertEqual(store.records(matching: "INVOICE").count, 2, "search must be case-insensitive")
    }

    @MainActor
    func testDeleteRemovesRecordAndBumpsRevision() throws {
        let store = try makeStore()
        store.add(record(text: "keep me"))
        store.add(record(text: "delete me"))
        let before = store.revision

        guard let victim = store.records(matching: "delete").first else {
            XCTFail("expected a record matching 'delete'")
            return
        }
        store.delete(victim)

        XCTAssertEqual(store.records(matching: "").map(\.cleanedText), ["keep me"])
        XCTAssertGreaterThan(store.revision, before)
    }

    @MainActor
    func testCorrectionRoundTripsAndEmptyClearsIt() throws {
        let store = try makeStore()
        store.add(record(text: "send the report wednesday"))
        guard let saved = store.records(matching: "").first else {
            XCTFail("expected the record back")
            return
        }
        store.setCorrected(saved, text: "  send the report thursday  ")
        XCTAssertEqual(store.records(matching: "").first?.correctedText, "send the report thursday")

        store.setCorrected(saved, text: "   ")
        XCTAssertNil(store.records(matching: "").first?.correctedText)
    }

    @MainActor
    func testVoteRoundTripsAndToggles() throws {
        let store = try makeStore()
        store.add(record(text: "flag me"))
        guard let saved = store.records(matching: "").first else {
            XCTFail("expected the record back")
            return
        }
        XCTAssertEqual(saved.vote, 0)
        store.setVote(saved, vote: -1)
        XCTAssertEqual(store.records(matching: "").first?.vote, -1)
        store.setVote(saved, vote: 0)
        XCTAssertEqual(store.records(matching: "").first?.vote, 0)
    }

    @MainActor
    func testClearRemovesEverything() throws {
        let store = try makeStore()
        store.add(record(text: "one"))
        store.add(record(text: "two"))
        store.clear()
        XCTAssertEqual(store.records(matching: ""), [])
    }
}
