import FluidAudio
import Foundation
import os

/// Audio bytes or a user-facing failure message.
enum TtsResult {
    case audio(Data)
    case failure(String)
}

/// Synthesizes speech audio for one chunk of text with the configured Kokoro
/// provider. Playback belongs to ReaderController; this only produces bytes.
@MainActor
final class TtsService {
    static let shared = TtsService()

    private let log = Logger(subsystem: "com.elliot.Murmur", category: "tts")
    private var kokoro: KokoroAneManager?

    /// Audio bytes (WAV from the built-in engine, MP3 from the server) or a
    /// user-facing failure message.
    func synthesize(_ text: String) async -> TtsResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure("Nothing to speak.") }
        switch SettingsStore.shared.ttsEngine {
        case .kokoro:
            return await synthesizeNative(trimmed)
        case .kokoroServer:
            return await synthesizeViaServer(trimmed)
        }
    }

    private func synthesizeNative(_ text: String) async -> TtsResult {
        do {
            if kokoro == nil {
                let manager = KokoroAneManager()
                // First run downloads the CoreML chain from HuggingFace.
                try await manager.initialize()
                kokoro = manager
            }
            guard let kokoro else { return .failure("Voice model failed to load.") }
            let wav = try await kokoro.synthesize(text: text)
            return .audio(wav)
        } catch {
            log.error("kokoro synth failed: \(error, privacy: .public)")
            return .failure("Voice synthesis failed. Relaunch and try again.")
        }
    }

    private func synthesizeViaServer(_ text: String) async -> TtsResult {
        guard let request = TtsRequestBuilder.speechRequest(
            engine: .kokoroServer, text: text, voice: SettingsStore.shared.ttsKokoroVoice
        ) else { return .failure("No server model configured.") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                log.error("tts server status \(status): \(String(data: data.prefix(200), encoding: .utf8) ?? "", privacy: .public)")
                return .failure("Voice server error (\(status)). Try again.")
            }
            return .audio(data)
        } catch {
            return .failure("Voice server not running. Start it with `make tts-serve`.")
        }
    }
}
