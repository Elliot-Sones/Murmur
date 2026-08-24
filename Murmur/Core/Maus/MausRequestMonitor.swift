import AppKit
import Observation
import os

/// Watches OpenMausBot's event stream for questions and permission requests and
/// surfaces the newest one in the pill, where the user answers by picking a
/// choice or typing a reply. A persistent, self-reconnecting listener: it holds
/// its own URLSession so a long-lived stream never trips MausClient's short
/// per-request timeout, and it resyncs from a fresh snapshot on every (re)connect.
@MainActor
@Observable
final class MausRequestMonitor {
    static let shared = MausRequestMonitor()

    /// The request the pill is currently asking about, if any.
    private(set) var current: PendingRequest?

    @ObservationIgnored private var inbox = PendingRequestInbox()
    @ObservationIgnored private var namesByThread: [String: String] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.elliot.Murmur", category: "maus-requests")

    @ObservationIgnored private let base = URL(string: "http://127.0.0.1:8799")!
    @ObservationIgnored private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 86_400
        return URLSession(configuration: config)
    }()

    /// Start listening if the feature is on; a no-op if already running or off.
    /// Toggling the setting calls this (or `stop`) to pick up the change.
    func startIfEnabled() {
        guard SettingsStore.shared.agentRequestsEnabled else { return stop() }
        guard loop == nil else { return }
        loop = Task { await run() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        inbox = PendingRequestInbox()
        publish()
    }

    // MARK: - Listen loop

    private func run() async {
        var backoff = Duration.seconds(1)
        while !Task.isCancelled {
            do {
                try await refreshSnapshot()
                try await consume()  // returns only when the stream ends
                backoff = .seconds(1)
            } catch {
                log.debug("event stream ended: \(error, privacy: .public)")
            }
            guard !Task.isCancelled else { break }
            try? await Task.sleep(for: backoff)
            backoff = min(backoff * 2, .seconds(30))
        }
    }

    /// Resync names and the full pending set. Any request answered while we
    /// were disconnected simply won't be in the snapshot, so it drops here.
    private func refreshSnapshot() async throws {
        let bots = try await MausClient.shared.listBots()
        namesByThread = Dictionary(bots.map { ($0.threadId, $0.name) }, uniquingKeysWith: { first, _ in first })
        inbox.replaceAll(try await MausClient.shared.pendingRequests())
        publish()
    }

    private func consume() async throws {
        var request = URLRequest(url: base.appendingPathComponent("api/events"))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 3600
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MausError.serverDown }
        for try await line in bytes.lines {
            if Task.isCancelled { return }
            guard line.hasPrefix("data:") else { continue }
            let payload = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
            guard let event = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                let kind = event["kind"] as? String
            else { continue }
            handle(kind: kind, event: event)
        }
    }

    private func handle(kind: String, event: [String: Any]) {
        switch kind {
        case "message", "message.patch":
            guard let threadId = event["threadId"] as? String,
                let message = event["message"] as? [String: Any]
            else { return }
            let name = namesByThread[threadId] ?? "Your bot"
            if let request = PendingRequest.from(message: message, threadId: threadId, botName: name) {
                inbox.upsert(request)
                publish()
            } else if PendingRequest.isResolved(message: message),
                let card = message["card"] as? [String: Any],
                let requestId = card["requestId"] as? String {
                inbox.resolve(requestId: requestId)
                publish()
            }
        case "bot":
            guard let bot = event["bot"] as? [String: Any],
                let threadId = bot["threadId"] as? String,
                let name = bot["name"] as? String
            else { return }
            namesByThread[threadId] = name
            inbox.relabel(threadId: threadId, botName: name)
            publish()
        case "runtime":
            // request.resolved is the provider settling a request from its own
            // side; retract it here too so a card answered in the app clears.
            guard let runtime = event["event"] as? [String: Any],
                (runtime["type"] as? String) == "request.resolved",
                let requestId = runtime["requestId"] as? String
            else { return }
            inbox.resolve(requestId: requestId)
            publish()
        default:
            break
        }
    }

    private func publish() {
        current = inbox.current
        if current != nil {
            PillPanelController.shared.show()
        } else {
            PillPanelController.shared.layout()
        }
    }

    // MARK: - Answering

    func allow() { answer(behavior: "allow") }
    func deny() { answer(behavior: "deny") }

    /// A button press on a choice. The Allow/Deny labels are permission
    /// behaviors; any other label is a question answer.
    func choose(_ choice: String) {
        switch choice {
        case "Allow": answer(behavior: "allow")
        case "Deny": answer(behavior: "deny")
        default: answer(behavior: "answer", message: choice)
        }
    }

    func submitTyped(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        answer(behavior: "answer", message: trimmed)
    }

    /// Wave the current request off the pill without answering it; it stays
    /// pending in OpenMausBot for the user to handle in the app.
    func dismissCurrent() {
        guard let request = current else { return }
        inbox.silence(requestId: request.requestId)
        publish()
    }

    private func answer(behavior: String, message: String? = nil) {
        guard let request = current else { return }
        let (threadId, requestId) = (request.threadId, request.requestId)
        // Optimistically clear the pill; a failed POST resurfaces it on the
        // next reconnect snapshot, and the app still shows it meanwhile.
        inbox.resolve(requestId: requestId)
        publish()
        Task {
            do {
                try await MausClient.shared.respond(
                    threadId: threadId, requestId: requestId, behavior: behavior, message: message
                )
            } catch {
                log.error("failed to answer request: \(error, privacy: .public)")
            }
        }
    }
}
