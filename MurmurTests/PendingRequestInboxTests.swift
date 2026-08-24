import XCTest

@testable import Murmur

final class PendingRequestInboxTests: XCTestCase {
    // MARK: - Classification from a message card

    private func message(kind: String = "options", card: [String: Any]?) -> [String: Any] {
        var m: [String: Any] = ["kind": kind]
        if let card { m["card"] = card }
        return m
    }

    func testPermissionCardClassifiedByTool() {
        let req = PendingRequest.from(
            message: message(card: [
                "requestId": "r1", "title": "Approval needed",
                "subtitle": "git push", "tool": "Bash", "options": ["Allow", "Deny"],
            ]),
            threadId: "t1", botName: "Sage")
        XCTAssertEqual(req?.kind, .permission)
        XCTAssertEqual(req?.choices, ["Allow", "Deny"])
        XCTAssertEqual(req?.detail, "git push")
        XCTAssertTrue(req?.isPermission == true)
    }

    func testLocalComputerScopeIsPermissionEvenWithoutTool() {
        let req = PendingRequest.from(
            message: message(card: [
                "requestId": "r2", "title": "Local computer approval",
                "subtitle": "open Safari", "approvalScope": "local-computer", "options": ["Allow", "Deny"],
            ]),
            threadId: "t1", botName: "Sage")
        XCTAssertEqual(req?.kind, .permission)
    }

    func testQuestionWithChoices() {
        let req = PendingRequest.from(
            message: message(card: [
                "requestId": "q1", "title": "Your bot has a question",
                "subtitle": "Which environment?", "options": ["Staging", "Production"],
            ]),
            threadId: "t2", botName: "Trajekt")
        XCTAssertEqual(req?.kind, .question)
        XCTAssertEqual(req?.choices, ["Staging", "Production"])
        XCTAssertFalse(req?.isPermission == true)
    }

    func testFreeTextQuestionHasNoChoices() {
        let req = PendingRequest.from(
            message: message(card: [
                "requestId": "q2", "title": "Your bot has a question",
                "subtitle": "What should I name the file?", "options": [String](),
            ]),
            threadId: "t2", botName: "Trajekt")
        XCTAssertEqual(req?.kind, .question)
        XCTAssertEqual(req?.choices, [])
    }

    func testAnsweredCardIsNotPending() {
        XCTAssertNil(
            PendingRequest.from(
                message: message(card: [
                    "requestId": "r3", "title": "Approval needed", "subtitle": "rm -rf",
                    "tool": "Bash", "answered": "allow",
                ]),
                threadId: "t1", botName: "Sage"))
    }

    func testDismissedCardIsNotPending() {
        XCTAssertNil(
            PendingRequest.from(
                message: message(card: ["requestId": "r4", "subtitle": "x", "dismissed": true]),
                threadId: "t1", botName: "Sage"))
    }

    func testNonOptionsMessageIsIgnored() {
        XCTAssertNil(
            PendingRequest.from(
                message: message(kind: "text", card: nil), threadId: "t1", botName: "Sage"))
        XCTAssertNil(
            PendingRequest.from(
                message: message(card: ["title": "no request id"]), threadId: "t1", botName: "Sage"))
    }

    func testIsResolved() {
        XCTAssertTrue(PendingRequest.isResolved(message: message(card: ["answered": "deny"])))
        XCTAssertTrue(PendingRequest.isResolved(message: message(card: ["dismissed": true])))
        XCTAssertFalse(PendingRequest.isResolved(message: message(card: ["requestId": "r"])))
        XCTAssertFalse(PendingRequest.isResolved(message: message(kind: "text", card: nil)))
    }

    // MARK: - Inbox behavior

    private func request(_ id: String, thread: String = "t1", name: String = "Sage") -> PendingRequest {
        PendingRequest(
            requestId: id, threadId: thread, botName: name, kind: .permission,
            title: "Approval needed", detail: "do \(id)", choices: ["Allow", "Deny"])
    }

    func testCurrentIsMostRecent() {
        var inbox = PendingRequestInbox()
        inbox.upsert(request("a"))
        inbox.upsert(request("b"))
        XCTAssertEqual(inbox.current?.requestId, "b")
    }

    func testResolveRemovesAndFallsBack() {
        var inbox = PendingRequestInbox()
        inbox.upsert(request("a"))
        inbox.upsert(request("b"))
        inbox.resolve(requestId: "b")
        XCTAssertEqual(inbox.current?.requestId, "a")
        inbox.resolve(requestId: "a")
        XCTAssertNil(inbox.current)
    }

    func testUpsertUpdatesInPlace() {
        var inbox = PendingRequestInbox()
        inbox.upsert(request("a"))
        var updated = request("a")
        updated.botName = "Renamed"
        inbox.upsert(updated)
        XCTAssertEqual(inbox.items.count, 1)
        XCTAssertEqual(inbox.current?.botName, "Renamed")
    }

    func testSilenceHidesWithoutRemoving() {
        var inbox = PendingRequestInbox()
        inbox.upsert(request("a"))
        inbox.silence(requestId: "a")
        XCTAssertNil(inbox.current)
        XCTAssertEqual(inbox.items.count, 1)
    }

    func testSilenceUnknownIdIsNoop() {
        var inbox = PendingRequestInbox()
        inbox.upsert(request("a"))
        inbox.silence(requestId: "ghost")
        XCTAssertEqual(inbox.current?.requestId, "a")
    }

    func testReplaceAllKeepsSilenceForPresentIds() {
        var inbox = PendingRequestInbox()
        inbox.upsert(request("a"))
        inbox.silence(requestId: "a")
        inbox.replaceAll([request("a"), request("b")])
        // "a" was silenced and is still present, so it stays silenced.
        XCTAssertEqual(inbox.current?.requestId, "b")
        inbox.resolve(requestId: "b")
        XCTAssertNil(inbox.current)
    }

    func testReplaceAllDropsSilenceForAbsentIds() {
        var inbox = PendingRequestInbox()
        inbox.upsert(request("a"))
        inbox.silence(requestId: "a")
        inbox.replaceAll([request("a")])
        inbox.replaceAll([])  // "a" gone entirely
        inbox.replaceAll([request("a")])  // reappears — no stale silence
        XCTAssertEqual(inbox.current?.requestId, "a")
    }

    func testRelabelUpdatesNamesForThread() {
        var inbox = PendingRequestInbox()
        inbox.upsert(request("a", thread: "t9", name: "Old"))
        inbox.relabel(threadId: "t9", botName: "New")
        XCTAssertEqual(inbox.current?.botName, "New")
    }
}
