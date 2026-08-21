import Foundation
import FoundationModels

/// Cleans transcripts with Apple's on-device model. Falls back to the raw
/// transcript on unavailability, guardrail refusal, error, or timeout, so the
/// user's words are never lost.
@MainActor
final class FoundationModelsCleanup: CleanupService {
    private let builder = CleanupPromptBuilder()
    private var session: LanguageModelSession?
    private let timeout: Duration = .seconds(3)

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func prewarm() {
        guard Self.isAvailable, session == nil else { return }
        let fresh = LanguageModelSession(instructions: builder.instructions())
        fresh.prewarm()
        session = fresh
    }

    func cleanup(_ raw: String) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isAvailable, !trimmed.isEmpty else { return raw }
        if session == nil { prewarm() }
        guard let session else { return raw }

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
            return cleaned.isEmpty ? raw : cleaned
        } catch {
            // A failed or overflowing session gets rebuilt on the next dictation.
            self.session = nil
            return raw
        }
    }
}
