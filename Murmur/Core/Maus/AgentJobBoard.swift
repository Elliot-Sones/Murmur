import Foundation

/// Pure state behind the agent activity dock: every in-flight quick-chat job,
/// its outcome, and which job (if any) is expanded into the detail face.
/// UI-free and timer-free so the transitions are unit-testable; the
/// controller owns tasks and expiry timers.
struct AgentJobBoard: Equatable {
    struct Job: Identifiable, Equatable {
        enum Phase: Equatable {
            case working
            case done(reply: String)
            case failed(message: String)
        }

        let id: UUID
        let agentName: String
        let botId: String?
        /// The bot's accent color name from the OpenMausBot API, if set.
        let color: String?
        /// The bot's custom avatar, if it has one.
        let avatarUrl: URL?
        var phase: Phase = .working

        var isWorking: Bool { if case .working = phase { return true }; return false }
        var isFailed: Bool { if case .failed = phase { return true }; return false }

        var statusText: String {
            switch phase {
            case .working: "Working…"
            case .done: "Replied"
            case .failed(let message): message
            }
        }
    }

    /// Icons the collapsed dock shows before folding the rest into "+N".
    static let maxVisibleIcons = 6

    private(set) var jobs: [Job] = []
    private(set) var expandedJobId: UUID?

    var isEmpty: Bool { jobs.isEmpty }
    var expandedJob: Job? { jobs.first { $0.id == expandedJobId } }
    var visibleJobs: [Job] { Array(jobs.prefix(Self.maxVisibleIcons)) }
    var overflowCount: Int { max(0, jobs.count - Self.maxVisibleIcons) }

    @discardableResult
    mutating func start(
        agentName: String, botId: String?, color: String? = nil,
        avatarUrl: URL? = nil, id: UUID = UUID()
    ) -> UUID {
        jobs.append(Job(id: id, agentName: agentName, botId: botId, color: color, avatarUrl: avatarUrl))
        return id
    }

    mutating func finish(_ id: UUID, reply: String) {
        update(id) { $0.phase = .done(reply: reply) }
    }

    mutating func fail(_ id: UUID, message: String) {
        update(id) { $0.phase = .failed(message: message) }
    }

    mutating func remove(_ id: UUID) {
        jobs.removeAll { $0.id == id }
        if expandedJobId == id { expandedJobId = nil }
    }

    /// A finished job whose linger ran out leaves the dock — unless the user
    /// is looking at it, or it failed (failures stay until dismissed).
    mutating func expireIfDone(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }),
            case .done = job.phase, expandedJobId != id
        else { return }
        remove(id)
    }

    mutating func toggleExpanded(_ id: UUID) {
        guard jobs.contains(where: { $0.id == id }) else { return }
        expandedJobId = expandedJobId == id ? nil : id
    }

    mutating func collapse() {
        expandedJobId = nil
    }

    private mutating func update(_ id: UUID, _ mutate: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
    }
}
