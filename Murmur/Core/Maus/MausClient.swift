import AppKit
import Foundation

/// One agent in OpenMausBot's local fleet.
struct MausBot: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let threadId: String
    let name: String
}

enum MausError: Error {
    case serverDown
    case badResponse(Int)
    case noReply
}

/// Talks to the OpenMausBot harness on localhost. The app is local-first:
/// the API answers on 127.0.0.1:8799 with no auth for same-machine callers.
actor MausClient {
    static let shared = MausClient()
    static let bundleId = "com.openmausbot.app"

    private let base = URL(string: "http://127.0.0.1:8799")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()

    func listBots() async throws -> [MausBot] {
        struct BotList: Decodable { let bots: [MausBot] }
        let data = try await get("/api/bots")
        return try JSONDecoder().decode(BotList.self, from: data).bots
    }

    /// The dedicated bot for unaddressed quick questions, created on first
    /// use: POST /api/bots makes a blank bot, PATCH names it.
    func findOrCreateMurmurBot() async throws -> MausBot {
        if let existing = try await listBots().first(where: { $0.name.lowercased() == "murmur" }) {
            return existing
        }
        struct Created: Decodable { let bot: MausBot }
        let created = try JSONDecoder().decode(
            Created.self, from: try await post("/api/bots", body: nil)
        ).bot
        _ = try await request(
            "PATCH", "/api/bots/\(created.id)/profile",
            body: [
                "name": "Murmur",
                "title": "Quick questions",
                "description": "Answers quick questions sent from the Murmur menu bar app's "
                    + "Option+Space chat. Keep replies short and self-contained; "
                    + "they are read in a small notification bubble.",
            ]
        )
        return MausBot(id: created.id, threadId: created.threadId, name: "Murmur")
    }

    func send(_ text: String, to botId: String) async throws {
        _ = try await post("/api/bots/\(botId)/messages", body: ["text": text])
    }

    /// Waits for the bot to finish its turn, then returns the turn's last
    /// assistant text. The event stream is only the completion signal (bot
    /// back to idle after having been busy, or an assistant message followed
    /// by idle); the reply text is then read from the thread, which is
    /// authoritative and free of stream-ordering races.
    func awaitReply(botId: String, threadId: String, timeout: Duration = .seconds(300)) async throws -> String {
        let sentAt = Date()
        var request = URLRequest(url: base.appendingPathComponent("api/events"))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 3600
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MausError.serverDown }

        let deadline = ContinuousClock.now + timeout
        var sawBusy = false
        var sawReplyEvent = false
        streaming: for try await line in bytes.lines {
            guard ContinuousClock.now < deadline else { break }
            guard line.hasPrefix("data:") else { continue }
            let payload = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
            guard let event = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                let kind = event["kind"] as? String
            else { continue }

            switch kind {
            case "message":
                if event["threadId"] as? String == threadId,
                    let message = event["message"] as? [String: Any],
                    message["role"] as? String == "bot" {
                    sawReplyEvent = true
                }
            case "bot":
                guard let bot = event["bot"] as? [String: Any],
                    bot["id"] as? String == botId,
                    let activity = bot["activity"] as? String
                else { continue }
                if activity != "idle" {
                    sawBusy = true
                } else if sawBusy || sawReplyEvent {
                    break streaming
                }
            default:
                continue
            }
        }

        // The turn is over (or timed out); read the outcome from the thread.
        // Replies carry role "bot"; kinds beyond plain text (option cards,
        // tool records) have no useful bubble text and are skipped.
        struct Page: Decodable { let messages: [Message] }
        struct Message: Decodable {
            let role: String?
            let kind: String?
            let text: String?
            let at: Double?
        }
        let data = try await get("/api/threads/\(threadId)/messages?limit=30")
        let messages = try JSONDecoder().decode(Page.self, from: data).messages
        let reply = messages.last { message in
            guard message.role == "bot",
                message.kind == "text",
                let text = message.text,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return false }
            // Only accept replies from this turn, not thread history.
            guard let at = message.at else { return true }
            return Date(timeIntervalSince1970: at / 1000) >= sentAt.addingTimeInterval(-5)
        }
        guard let reply, let text = reply.text else { throw MausError.noReply }
        return text
    }

    @MainActor
    static func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - HTTP plumbing

    private func get(_ path: String) async throws -> Data {
        try await request("GET", path, body: nil)
    }

    private func post(_ path: String, body: [String: String]?) async throws -> Data {
        try await request("POST", path, body: body)
    }

    @discardableResult
    private func request(_ method: String, _ path: String, body: [String: String]?) async throws -> Data {
        guard let url = URL(string: path, relativeTo: base) else { throw MausError.serverDown }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MausError.serverDown
        }
        guard let http = response as? HTTPURLResponse else { throw MausError.serverDown }
        guard (200..<300).contains(http.statusCode) else { throw MausError.badResponse(http.statusCode) }
        return data
    }
}
