import Foundation
import FoundationModels

/// Cleans transcripts with Apple's on-device model. Falls back to the raw
/// transcript on unavailability, guardrail refusal, error, or timeout, so the
/// user's words are never lost. The session is rebuilt when the cleanup
/// context (dictionary, tone) changes.
@MainActor
final class FoundationModelsCleanup: CleanupService {
    private let builder = CleanupPromptBuilder()
    private var session: LanguageModelSession?
    private var sessionKey: String?
    private let timeout: Duration = .seconds(3)

    /// What actually happened on the most recent cleanup call.
    private(set) var lastOutcome = "not run yet"

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func prewarm(context: CleanupContext = CleanupContext()) {
        guard Self.isAvailable else { return }
        let key = Self.key(for: context)
        guard session == nil || sessionKey != key else { return }
        let fresh = LanguageModelSession(
            instructions: builder.instructions(
                dictionary: context.dictionary, toneHint: context.toneHint
            )
        )
        fresh.prewarm()
        session = fresh
        sessionKey = key
    }

    func cleanup(_ raw: String, context: CleanupContext) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isAvailable else {
            lastOutcome = "raw (Apple Intelligence unavailable)"
            return raw
        }
        guard !trimmed.isEmpty else { return raw }
        prewarm(context: context)
        guard let session else {
            lastOutcome = "raw (no session)"
            return raw
        }

        // The 3B model treats destination metadata too literally: it echoes
        // the line into the output or invents headers ("Subject:") to match
        // the app. Destination context is Ollama-only; app tone for this
        // engine comes from profile instructions instead.
        let prompt = builder.userPrompt(rawTranscript: trimmed)
        let responseTask = Task { @MainActor in
            try await session.respond(to: prompt).content
        }
        let timeoutTask = Task { [timeout] in
            try? await Task.sleep(for: timeout)
            responseTask.cancel()
        }
        defer { timeoutTask.cancel() }

        do {
            let cleaned = try await responseTask.value
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lastOutcome = "Apple on-device model"
            return cleaned.isEmpty ? raw : cleaned
        } catch is CancellationError {
            resetSession()
            lastOutcome = "raw (model timed out)"
            return raw
        } catch {
            // A failed or overflowing session gets rebuilt on the next dictation.
            resetSession()
            lastOutcome = "raw (model error)"
            return raw
        }
    }

    private func resetSession() {
        session = nil
        sessionKey = nil
    }

    private static func key(for context: CleanupContext) -> String {
        context.dictionary.joined(separator: "|") + "§" + (context.toneHint ?? "")
    }
}
