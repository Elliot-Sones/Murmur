import Foundation
import Observation
import os

/// Sends a meeting transcript to the Sage agent in OpenMausBot and asks it to
/// extract Elliot's action items, then stores the reply as the meeting summary.
@MainActor
@Observable
final class MeetingSummarizer {
    static let shared = MeetingSummarizer()

    enum Status: Equatable {
        case idle
        case sending
        case failed(String)
    }

    private let log = Logger(subsystem: "com.elliot.Murmur", category: "meeting-summary")
    private var statuses: [String: Status] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    /// Bumped so the UI (which reads status(for:)) re-renders on change.
    private(set) var revision = 0

    func status(for id: String) -> Status { statuses[id] ?? .idle }

    /// Sends the meeting to Sage and saves its reply as the summary.
    func summarize(meetingId: String, title: String, date: Date, transcript: String) {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus(.failed("No transcript to summarize yet."), for: meetingId)
            return
        }
        tasks[meetingId]?.cancel()
        setStatus(.sending, for: meetingId)
        let prompt = Self.prompt(title: title, date: date, transcript: transcript)
        tasks[meetingId] = Task {
            do {
                guard let sage = try await MausClient.shared.findBot(named: "Sage") else {
                    setStatus(.failed("Couldn't find the Sage agent in OpenMausBot."), for: meetingId)
                    return
                }
                try await MausClient.shared.send(prompt, to: sage.id)
                let reply = try await MausClient.shared.awaitReply(
                    botId: sage.id, threadId: sage.threadId
                )
                guard !Task.isCancelled else { return }
                MeetingStore.shared.saveSummary(reply, for: meetingId)
                setStatus(.idle, for: meetingId)
                log.notice("summary saved for \(meetingId, privacy: .public)")
            } catch {
                guard !Task.isCancelled else { return }
                log.error("summary failed: \(error, privacy: .public)")
                setStatus(
                    .failed("Sage didn't answer. Make sure OpenMausBot is running, then retry."),
                    for: meetingId
                )
            }
        }
    }

    func cancel(_ meetingId: String) {
        tasks[meetingId]?.cancel()
        setStatus(.idle, for: meetingId)
    }

    private func setStatus(_ status: Status, for id: String) {
        statuses[id] = status
        revision += 1
    }

    private static func prompt(title: String, date: Date, transcript: String) -> String {
        let dateText = date.formatted(date: .abbreviated, time: .shortened)
        return """
            You are Sage, Elliot's assistant. Below is a transcript of a meeting Elliot \
            attended. "Me" is Elliot; "Them" is everyone else on the call.

            Read the whole transcript and extract a clear, deduplicated list of concrete \
            action items that ELLIOT personally needs to do. Owner is Elliot: skip tasks \
            that belong to other people unless Elliot has to follow up on them. Keep each \
            item short and actionable, and include any due date or timing that was \
            mentioned. Reply with ONLY a numbered list of tasks and no preamble. If there \
            are no action items for Elliot, reply exactly: No action items for you.

            Meeting: \(title) (\(dateText))

            Transcript:
            \(transcript)
            """
    }
}
