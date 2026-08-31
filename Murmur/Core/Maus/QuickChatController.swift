import AppKit
import Observation
import os

/// Option+Space quick chat: a typed message to one OpenMausBot agent (or the
/// dedicated "Murmur" bot when no agent is chosen). Each send becomes a job
/// on the agent activity dock in the pill widget; several agents can run at
/// once. Clicking a job's icon expands its detail (reply, cancel, open app).
@MainActor
@Observable
final class QuickChatController {
    static let shared = QuickChatController()

    private let log = Logger(subsystem: "com.elliot.Murmur", category: "quickchat")

    private(set) var agents: [MausBot] = []
    var selectedAgentId: String?
    var draft = ""
    private(set) var board = AgentJobBoard() {
        didSet { PillPanelController.shared.layout() }
    }

    private var jobTasks: [UUID: Task<Void, Never>] = [:]
    private var expireTasks: [UUID: Task<Void, Never>] = [:]

    func togglePanel() {
        if QuickChatPanelController.shared.isVisible {
            QuickChatPanelController.shared.hide()
            return
        }
        draft = ""
        QuickChatPanelController.shared.show()
        Task {
            // Refresh the fleet in the background; the panel opens instantly.
            if let bots = try? await MausClient.shared.listBots() {
                agents = bots.filter { $0.name.lowercased() != "murmur" && $0.hidden != true }
                if let selectedAgentId, !agents.contains(where: { $0.id == selectedAgentId }) {
                    self.selectedAgentId = nil
                }
            }
        }
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let agentId = selectedAgentId
        draft = ""
        QuickChatPanelController.shared.hide()

        let chosen = agentId.flatMap { id in agents.first { $0.id == id } }
        let jobId = board.start(
            agentName: chosen?.name ?? "Murmur",
            botId: chosen?.id,
            color: chosen?.color,
            avatarUrl: chosen?.avatarUrl.flatMap(URL.init(string:))
        )
        PillPanelController.shared.show()

        jobTasks[jobId] = Task {
            defer { jobTasks[jobId] = nil }
            let bot: MausBot
            if let chosen {
                bot = chosen
            } else {
                do {
                    bot = try await MausClient.shared.findOrCreateMurmurBot()
                } catch {
                    fail(jobId, "OpenMausBot isn't running. Click to open it.", error: error)
                    return
                }
            }
            do {
                try await MausClient.shared.send(text, to: bot.id)
                let reply = try await MausClient.shared.awaitReply(
                    botId: bot.id, threadId: bot.threadId
                )
                guard !Task.isCancelled else { return }
                board.finish(jobId, reply: reply)
                scheduleExpiry(of: jobId, after: .seconds(45))
            } catch {
                guard !Task.isCancelled else { return }
                fail(jobId, "No reply from \(bot.name). Click to open OpenMausBot.", error: error)
            }
        }
    }

    // MARK: - Dock actions

    func toggleExpanded(_ id: UUID) {
        board.toggleExpanded(id)
    }

    func collapse() {
        board.collapse()
    }

    /// Stop a running job and drop it from the dock.
    func cancel(_ id: UUID) {
        jobTasks[id]?.cancel()
        jobTasks[id] = nil
        dismiss(id)
    }

    func dismiss(_ id: UUID) {
        expireTasks[id]?.cancel()
        expireTasks[id] = nil
        board.remove(id)
    }

    /// Click-through from a reply or failure: open the app, drop the job.
    func openMausAndDismiss(_ id: UUID) {
        MausClient.openApp()
        dismiss(id)
    }

    // MARK: - Internals

    private func fail(_ id: UUID, _ message: String, error: Error) {
        log.error("quick chat failed: \(error, privacy: .public)")
        board.fail(id, message: message)
        PillPanelController.shared.show()
    }

    private func scheduleExpiry(of id: UUID, after delay: Duration) {
        expireTasks[id]?.cancel()
        expireTasks[id] = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            expireTasks[id] = nil
            board.expireIfDone(id)
        }
    }
}
