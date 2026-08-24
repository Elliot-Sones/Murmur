import AppKit
import Observation
import os

/// Option+Space quick chat: a typed message to one OpenMausBot agent (or the
/// dedicated "Murmur" bot when no agent is chosen), with the reply surfaced
/// in the pill widget. Clicking the reply opens OpenMausBot.
@MainActor
@Observable
final class QuickChatController {
    static let shared = QuickChatController()

    /// The pill's quick-chat face, shown alongside the dictation faces.
    enum Bubble: Equatable {
        case waiting(agent: String)
        case reply(agent: String, text: String)
        case failure(String)
    }

    private let log = Logger(subsystem: "com.elliot.Murmur", category: "quickchat")

    private(set) var agents: [MausBot] = []
    var selectedAgentId: String?
    var draft = ""
    private(set) var bubble: Bubble? {
        didSet { PillPanelController.shared.layout() }
    }

    private var replyTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?

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
                agents = bots.filter { $0.name.lowercased() != "murmur" }
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

        replyTask?.cancel()
        dismissTask?.cancel()
        replyTask = Task {
            let bot: MausBot
            do {
                if let agentId, let chosen = agents.first(where: { $0.id == agentId }) {
                    bot = chosen
                } else {
                    bot = try await MausClient.shared.findOrCreateMurmurBot()
                }
            } catch {
                showFailure("OpenMausBot isn't running. Click to open it.", error: error)
                return
            }
            bubble = .waiting(agent: bot.name)
            PillPanelController.shared.show()
            do {
                try await MausClient.shared.send(text, to: bot.id)
                let reply = try await MausClient.shared.awaitReply(
                    botId: bot.id, threadId: bot.threadId
                )
                guard !Task.isCancelled else { return }
                bubble = .reply(agent: bot.name, text: reply)
                scheduleDismiss(after: .seconds(45))
            } catch {
                guard !Task.isCancelled else { return }
                showFailure("No reply from \(bot.name). Click to open OpenMausBot.", error: error)
            }
        }
    }

    /// Click-through on the bubble: open the app, drop the bubble.
    func openMausAndDismiss() {
        MausClient.openApp()
        dismissBubble()
    }

    func dismissBubble() {
        replyTask?.cancel()
        dismissTask?.cancel()
        bubble = nil
    }

    private func showFailure(_ message: String, error: Error) {
        log.error("quick chat failed: \(error, privacy: .public)")
        bubble = .failure(message)
        PillPanelController.shared.show()
        scheduleDismiss(after: .seconds(20))
    }

    private func scheduleDismiss(after delay: Duration) {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            bubble = nil
        }
    }
}
