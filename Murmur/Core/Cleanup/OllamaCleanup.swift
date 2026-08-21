import Foundation

/// Cleans transcripts through a local Ollama server. Falls back to the raw
/// transcript on any failure, like every cleanup engine.
@MainActor
final class OllamaCleanup: CleanupService {
    private let builder = CleanupPromptBuilder()
    private let session: URLSession

    private(set) var lastOutcome = "not run yet"

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        session = URLSession(configuration: configuration)
    }

    func cleanup(_ raw: String, context: CleanupContext) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        let model = SettingsStore.shared.ollamaModel
        guard !model.isEmpty else {
            lastOutcome = "raw (no Ollama model selected)"
            return raw
        }

        var request = URLRequest(url: OllamaAPI.baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = OllamaAPI.chatRequestBody(
            model: model,
            instructions: builder.instructions(
                dictionary: context.dictionary, toneHint: context.toneHint
            ),
            prompt: builder.userPrompt(
                rawTranscript: trimmed,
                appName: context.appName,
                windowTitle: context.windowTitle
            )
        )

        do {
            let (data, _) = try await session.data(for: request)
            guard let content = OllamaAPI.parseChatResponse(data) else {
                lastOutcome = "raw (Ollama bad response)"
                return raw
            }
            let cleaned = CleanupOutputSanitizer.sanitize(content, rawTranscript: trimmed)
            lastOutcome = "Ollama (\(model))"
            return cleaned.isEmpty ? raw : cleaned
        } catch {
            lastOutcome = "raw (Ollama unreachable or timed out)"
            return raw
        }
    }

    /// Model names from the local server, or empty when it is not running.
    nonisolated static func availableModels() async -> [String] {
        var request = URLRequest(url: OllamaAPI.baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }
        return OllamaAPI.parseTags(data)
    }
}
