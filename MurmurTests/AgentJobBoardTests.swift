import XCTest

@testable import Murmur

final class AgentJobBoardTests: XCTestCase {
    private var board = AgentJobBoard()

    // MARK: - Multiple simultaneous agents

    func testStartsSeveralJobsAtOnce() {
        let a = board.start(agentName: "NTangible", botId: "b1")
        let b = board.start(agentName: "Sage", botId: "b2")
        XCTAssertEqual(board.jobs.count, 2)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(board.jobs.allSatisfy(\.isWorking))
    }

    func testVisibleAndOverflowSplit() {
        for index in 0..<9 {
            board.start(agentName: "Bot\(index)", botId: "b\(index)")
        }
        XCTAssertEqual(board.visibleJobs.count, AgentJobBoard.maxVisibleIcons)
        XCTAssertEqual(board.overflowCount, 9 - AgentJobBoard.maxVisibleIcons)
        XCTAssertEqual(board.visibleJobs.first?.agentName, "Bot0")
    }

    func testNoOverflowUnderTheCap() {
        board.start(agentName: "NTangible", botId: "b1")
        XCTAssertEqual(board.overflowCount, 0)
    }

    // MARK: - Completion

    func testFinishMarksDoneAndKeepsJob() {
        let id = board.start(agentName: "NTangible", botId: "b1")
        board.finish(id, reply: "Done!")
        XCTAssertEqual(board.jobs.first?.phase, .done(reply: "Done!"))
    }

    func testExpiryRemovesDoneJob() {
        let id = board.start(agentName: "NTangible", botId: "b1")
        board.finish(id, reply: "Done!")
        board.expireIfDone(id)
        XCTAssertTrue(board.isEmpty)
    }

    func testExpirySkipsExpandedJob() {
        let id = board.start(agentName: "NTangible", botId: "b1")
        board.finish(id, reply: "Done!")
        board.toggleExpanded(id)
        board.expireIfDone(id)
        XCTAssertEqual(board.jobs.count, 1)
    }

    func testExpiryOnlyTouchesItsOwnJob() {
        let a = board.start(agentName: "NTangible", botId: "b1")
        let b = board.start(agentName: "Sage", botId: "b2")
        board.finish(a, reply: "Done!")
        board.expireIfDone(a)
        XCTAssertEqual(board.jobs.map(\.id), [b])
    }

    // MARK: - Failure

    func testFailedJobSurvivesExpiry() {
        let id = board.start(agentName: "NTangible", botId: "b1")
        board.fail(id, message: "No reply")
        board.expireIfDone(id)
        XCTAssertEqual(board.jobs.count, 1)
        XCTAssertTrue(board.jobs[0].isFailed)
    }

    func testWorkingJobSurvivesExpiry() {
        let id = board.start(agentName: "NTangible", botId: "b1")
        board.expireIfDone(id)
        XCTAssertEqual(board.jobs.count, 1)
    }

    // MARK: - Expansion

    func testToggleExpandAndCollapse() {
        let id = board.start(agentName: "NTangible", botId: "b1")
        board.toggleExpanded(id)
        XCTAssertEqual(board.expandedJob?.id, id)
        board.toggleExpanded(id)
        XCTAssertNil(board.expandedJob)
    }

    func testExpandingAnotherJobMovesExpansion() {
        let a = board.start(agentName: "NTangible", botId: "b1")
        let b = board.start(agentName: "Sage", botId: "b2")
        board.toggleExpanded(a)
        board.toggleExpanded(b)
        XCTAssertEqual(board.expandedJob?.id, b)
    }

    func testExpandingUnknownJobDoesNothing() {
        board.start(agentName: "NTangible", botId: "b1")
        board.toggleExpanded(UUID())
        XCTAssertNil(board.expandedJob)
    }

    // MARK: - Cancellation / dismissal

    func testRemoveDropsJobAndItsExpansion() {
        let id = board.start(agentName: "NTangible", botId: "b1")
        board.toggleExpanded(id)
        board.remove(id)
        XCTAssertTrue(board.isEmpty)
        XCTAssertNil(board.expandedJob)
    }

    func testRemoveLeavesOtherJobsAlone() {
        let a = board.start(agentName: "NTangible", botId: "b1")
        let b = board.start(agentName: "Sage", botId: "b2")
        board.remove(a)
        XCTAssertEqual(board.jobs.map(\.id), [b])
    }
}
