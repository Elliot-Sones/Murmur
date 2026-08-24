import XCTest

@testable import Murmur

@MainActor
final class MeetingStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    func testCreateAppendFinishRoundTrip() {
        let store = MeetingStore(root: tempRoot)
        let record = store.create(title: "Standup")
        store.append(MeetingSegment(source: "me", offset: 0, text: "Morning everyone"), to: record.id)
        store.append(MeetingSegment(source: "them", offset: 11, text: "Morning"), to: record.id)
        store.finish(record.id, duration: 90)

        let reloaded = MeetingStore(root: tempRoot)
        XCTAssertEqual(reloaded.meetings.count, 1)
        let meeting = reloaded.meetings[0]
        XCTAssertEqual(meeting.title, "Standup")
        XCTAssertEqual(meeting.state, "done")
        XCTAssertEqual(meeting.durationSeconds, 90)
        XCTAssertEqual(meeting.segments.map(\.text), ["Morning everyone", "Morning"])
        XCTAssertEqual(meeting.segments.map(\.source), ["me", "them"])
    }

    func testSegmentsInterleaveByOffset() {
        let store = MeetingStore(root: tempRoot)
        let record = store.create(title: "Call")
        store.append(MeetingSegment(source: "them", offset: 11, text: "b"), to: record.id)
        store.append(MeetingSegment(source: "me", offset: 5, text: "a"), to: record.id)
        store.append(MeetingSegment(source: "me", offset: 22, text: "c"), to: record.id)

        let texts = store.meetings[0].segments.map(\.text)
        XCTAssertEqual(texts, ["a", "b", "c"])
    }

    func testCrashedMeetingReloadsAsDoneWithTranscript() {
        let store = MeetingStore(root: tempRoot)
        let record = store.create(title: "Crash test")
        store.append(MeetingSegment(source: "me", offset: 0, text: "survives"), to: record.id)
        // No finish(): simulates the app dying mid-meeting.

        let reloaded = MeetingStore(root: tempRoot)
        XCTAssertEqual(reloaded.meetings.count, 1)
        XCTAssertEqual(reloaded.meetings[0].state, "done")
        XCTAssertEqual(reloaded.meetings[0].segments.map(\.text), ["survives"])
    }

    func testNotesPersistAndDeleteRemovesEverything() {
        let store = MeetingStore(root: tempRoot)
        let record = store.create(title: "Notes")
        store.saveNotes("remember the budget", for: record.id)

        let reloaded = MeetingStore(root: tempRoot)
        XCTAssertEqual(reloaded.meetings[0].notes, "remember the budget")

        reloaded.delete(record.id)
        XCTAssertTrue(reloaded.meetings.isEmpty)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: tempRoot.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty)
    }
}
