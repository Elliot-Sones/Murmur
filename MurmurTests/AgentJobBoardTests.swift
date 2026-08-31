import XCTest

@testable import Murmur

final class AgentJobBoardTests: XCTestCase {
    private var board = AgentJobBoard()

    // MARK: - Multiple simultaneous agents

    func testStartsSeveralJobsAtOnce() {
        let a = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        let b = board.start(agentName: "Sage", botId: "b2", prompt: "hi")
        XCTAssertEqual(board.jobs.count, 2)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(board.jobs.allSatisfy(\.isWorking))
    }

    func testVisibleAndOverflowSplit() {
        for index in 0..<9 {
            board.start(agentName: "Bot\(index)", botId: "b\(index)", prompt: "hi")
        }
        XCTAssertEqual(board.visibleJobs.count, AgentJobBoard.maxVisibleIcons)
        XCTAssertEqual(board.overflowCount, 9 - AgentJobBoard.maxVisibleIcons)
        XCTAssertEqual(board.visibleJobs.first?.agentName, "Bot0")
    }

    func testNoOverflowUnderTheCap() {
        board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        XCTAssertEqual(board.overflowCount, 0)
    }

    // MARK: - Completion

    func testFinishMarksDoneAndKeepsJob() {
        let id = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        board.finish(id, reply: "Done!")
        XCTAssertEqual(board.jobs.first?.phase, .done(reply: "Done!"))
    }

    func testExpiryRemovesDoneJob() {
        let id = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        board.finish(id, reply: "Done!")
        board.expireIfDone(id)
        XCTAssertTrue(board.isEmpty)
    }

    func testExpirySkipsExpandedJob() {
        let id = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        board.finish(id, reply: "Done!")
        board.toggleExpanded(id)
        board.expireIfDone(id)
        XCTAssertEqual(board.jobs.count, 1)
    }

    func testExpiryOnlyTouchesItsOwnJob() {
        let a = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        let b = board.start(agentName: "Sage", botId: "b2", prompt: "hi")
        board.finish(a, reply: "Done!")
        board.expireIfDone(a)
        XCTAssertEqual(board.jobs.map(\.id), [b])
    }

    // MARK: - Failure

    func testFailedJobSurvivesExpiry() {
        let id = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        board.fail(id, message: "No reply")
        board.expireIfDone(id)
        XCTAssertEqual(board.jobs.count, 1)
        XCTAssertTrue(board.jobs[0].isFailed)
    }

    func testWorkingJobSurvivesExpiry() {
        let id = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        board.expireIfDone(id)
        XCTAssertEqual(board.jobs.count, 1)
    }

    // MARK: - Expansion

    func testToggleExpandAndCollapse() {
        let id = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        board.toggleExpanded(id)
        XCTAssertEqual(board.expandedJob?.id, id)
        board.toggleExpanded(id)
        XCTAssertNil(board.expandedJob)
    }

    func testExpandingAnotherJobMovesExpansion() {
        let a = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        let b = board.start(agentName: "Sage", botId: "b2", prompt: "hi")
        board.toggleExpanded(a)
        board.toggleExpanded(b)
        XCTAssertEqual(board.expandedJob?.id, b)
    }

    func testExpandingUnknownJobDoesNothing() {
        board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        board.toggleExpanded(UUID())
        XCTAssertNil(board.expandedJob)
    }

    // MARK: - Follow-ups

    func testStartRecordsThePromptAsFirstTurn() {
        let id = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        XCTAssertEqual(board.jobs.first?.turns.map(\.text), ["hi"])
        XCTAssertEqual(board.jobs.first?.turns.first?.role, .user)
        _ = id
    }

    func testFinishAppendsBotTurn() {
        let id = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        board.finish(id, reply: "hello")
        XCTAssertEqual(board.jobs.first?.turns.map(\.text), ["hi", "hello"])
        XCTAssertEqual(board.jobs.first?.turns.last?.role, .bot)
    }

    func testAskAppendsUserTurnAndReturnsToWorking() {
        let id = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        board.finish(id, reply: "hello")
        board.ask(id, text: "more?")
        XCTAssertEqual(board.jobs.first?.turns.count, 3)
        XCTAssertTrue(board.jobs.first!.isWorking)
    }

    func testAssignBotFillsIdentity() {
        let id = board.start(agentName: "Murmur", botId: nil, prompt: "hi")
        board.assignBot(id, botId: "b9", threadId: "t9", name: "Murmur", color: "yellow")
        XCTAssertEqual(board.jobs.first?.botId, "b9")
        XCTAssertEqual(board.jobs.first?.threadId, "t9")
        XCTAssertEqual(board.jobs.first?.color, "yellow")
    }

    // MARK: - Cancellation / dismissal

    func testRemoveDropsJobAndItsExpansion() {
        let id = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        board.toggleExpanded(id)
        board.remove(id)
        XCTAssertTrue(board.isEmpty)
        XCTAssertNil(board.expandedJob)
    }

    func testRemoveLeavesOtherJobsAlone() {
        let a = board.start(agentName: "NTangible", botId: "b1", prompt: "hi")
        let b = board.start(agentName: "Sage", botId: "b2", prompt: "hi")
        board.remove(a)
        XCTAssertEqual(board.jobs.map(\.id), [b])
    }
}
