import Foundation
import FoundationModels

/// Command mode engine: rewrites selected text per a spoken instruction.
/// Prefers the configured Ollama model (bigger, better at rewriting), falls
/// back to Apple's on-device model. Returns nil when every engine fails, so
/// the caller never destroys the selection with a bad result.
@MainActor
final class Rewriter {
    private let builder = RewritePromptBuilder()
    private(set) var lastOutcome = "not run yet"

    private let ollamaSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    func rewrite(selection: String, instruction: String) async -> String? {
        let model = SettingsStore.shared.ollamaModel
        if !model.isEmpty,
            let viaOllama = await ollamaRewrite(
                model: model, selection: selection, instruction: instruction
            ) {
            lastOutcome = "Ollama (\(model))"
            return viaOllama
        }
        if let viaApple = await foundationRewrite(selection: selection, instruction: instruction) {
            lastOutcome = model.isEmpty
                ? "Apple on-device model"
                : "Apple on-device model (Ollama unavailable)"
            return viaApple
        }
        lastOutcome = "failed (no rewrite engine available)"
        return nil
    }

    private func ollamaRewrite(
        model: String, selection: String, instruction: String
    ) async -> String? {
        var request = URLRequest(url: OllamaAPI.baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = OllamaAPI.chatRequestBody(
            model: model,
            instructions: builder.instructions(),
            prompt: builder.userPrompt(selection: selection, instruction: instruction)
        )
        guard let (data, _) = try? await ollamaSession.data(for: request),
            let content = OllamaAPI.parseChatResponse(data)
        else { return nil }
        let sanitized = CleanupOutputSanitizer.sanitize(content, rawTranscript: selection)
        return sanitized.isEmpty ? nil : sanitized
    }

    private func foundationRewrite(selection: String, instruction: String) async -> String? {
        guard FoundationModelsCleanup.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: builder.instructions())
        let prompt = builder.userPrompt(selection: selection, instruction: instruction)

        let responseTask = Task { @MainActor in
            try await session.respond(to: prompt).content
        }
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(8))
            responseTask.cancel()
        }
        defer { timeoutTask.cancel() }

        guard let content = try? await responseTask.value else { return nil }
        let sanitized = CleanupOutputSanitizer.sanitize(content, rawTranscript: selection)
        return sanitized.isEmpty ? nil : sanitized
    }
}
