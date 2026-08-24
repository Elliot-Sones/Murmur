import Foundation

/// A bot's pending permission request or question, surfaced from OpenMausBot's
/// event stream so the pill can ask the user and take an answer. A value type,
/// Sendable — safe to build off the network path and hand to the MainActor.
struct PendingRequest: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A tool approval: answered Allow or Deny.
        case permission
        /// A question: answered by picking a choice or typing a reply.
        case question
    }

    let requestId: String
    let threadId: String
    var botName: String
    let kind: Kind
    /// The card headline, e.g. "Approval needed" or "Local computer approval".
    let title: String
    /// The concrete thing being asked: the command, path, or question text.
    let detail: String
    /// Buttons to offer. Permission: ["Allow", "Deny"]. Question: its options,
    /// which may be empty (a free-text question, answered by typing only).
    let choices: [String]

    var id: String { requestId }
    var isPermission: Bool { kind == .permission }
}

extension PendingRequest {
    /// Build from an OpenMausBot `message` object (the payload of a `message`
    /// or `message.patch` SSE event, or an entry in `/api/bots`), if and only
    /// if it is an actionable request still awaiting the user. Answered or
    /// dismissed cards are history and return nil.
    static func from(message: [String: Any], threadId: String, botName: String) -> PendingRequest? {
        guard (message["kind"] as? String) == "options",
            let card = message["card"] as? [String: Any],
            let requestId = card["requestId"] as? String,
            !requestId.isEmpty
        else { return nil }
        if isResolvedCard(card) { return nil }

        let title = (card["title"] as? String) ?? "Your bot"
        let detail = (card["subtitle"] as? String) ?? ""
        let options = (card["options"] as? [String]) ?? []
        // A permission carries a tool, or the local-computer scope, or the
        // canonical Allow/Deny pair; everything else is a question.
        let permission =
            card["tool"] != nil
            || (card["approvalScope"] as? String) == "local-computer"
            || options == ["Allow", "Deny"]

        return PendingRequest(
            requestId: requestId,
            threadId: threadId,
            botName: botName,
            kind: permission ? .permission : .question,
            title: title,
            detail: detail,
            choices: permission ? ["Allow", "Deny"] : options
        )
    }

    /// True when this message's card has been answered or dismissed — used to
    /// retract a pending request when a later patch settles it.
    static func isResolved(message: [String: Any]) -> Bool {
        guard let card = message["card"] as? [String: Any] else { return false }
        return isResolvedCard(card)
    }

    private static func isResolvedCard(_ card: [String: Any]) -> Bool {
        if let answered = card["answered"] as? String, !answered.isEmpty { return true }
        if (card["dismissed"] as? Bool) == true { return true }
        return false
    }
}

/// The set of requests currently awaiting the user, newest last. Pure and
/// deterministic: the monitor feeds it parsed events and reads `current` back
/// for the pill. Kept out of the monitor so it can be unit-tested on its own.
struct PendingRequestInbox: Equatable {
    private(set) var items: [PendingRequest] = []
    /// Requests the user waved off in the pill without answering them in the
    /// app; they stay pending in OpenMausBot but leave the pill alone.
    private(set) var silenced: Set<String> = []

    /// What the pill should show: the most recent request not yet answered
    /// here or silenced.
    var current: PendingRequest? {
        items.last { !silenced.contains($0.requestId) }
    }

    mutating func upsert(_ request: PendingRequest) {
        if let index = items.firstIndex(where: { $0.requestId == request.requestId }) {
            items[index] = request
        } else {
            items.append(request)
        }
    }

    mutating func resolve(requestId: String) {
        items.removeAll { $0.requestId == requestId }
        silenced.remove(requestId)
    }

    mutating func silence(requestId: String) {
        guard items.contains(where: { $0.requestId == requestId }) else { return }
        silenced.insert(requestId)
    }

    /// Adopt a fresh full snapshot (the initial `/api/bots` scan or a
    /// post-reconnect resync), keeping local silences for ids still present.
    mutating func replaceAll(_ requests: [PendingRequest]) {
        items = requests
        silenced = silenced.intersection(requests.map(\.requestId))
    }

    /// Keep a bot's display name current as the roster loads or changes.
    mutating func relabel(threadId: String, botName: String) {
        for index in items.indices where items[index].threadId == threadId {
            items[index].botName = botName
        }
    }
}
