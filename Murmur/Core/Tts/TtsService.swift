import AVFoundation
import FluidAudio
import Foundation
import os

/// Speaks text through the engine chosen in Settings. Returns a user-facing
/// error message on failure, nil on success.
@MainActor
final class TtsService {
    static let shared = TtsService()

    private let log = Logger(subsystem: "com.elliot.Murmur", category: "tts")
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var kokoro: KokoroAneManager?
    private var speakTask: Task<Void, Never>?

    func speakLatest(_ text: String) async -> String? {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Nothing to speak." }
        switch SettingsStore.shared.ttsEngine {
        case .system:
            speakWithSystemVoice(trimmed)
            return nil
        case .kokoro:
            return await speakWithKokoro(trimmed)
        case .kokoroServer, .chatterbox, .qwen:
            return await speakViaServer(trimmed)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
    }

    private func speakWithSystemVoice(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        if let personal = AVSpeechSynthesisVoice.speechVoices()
            .first(where: { $0.voiceTraits.contains(.isPersonalVoice) }) {
            utterance.voice = personal
        }
        synthesizer.speak(utterance)
    }

    private func speakWithKokoro(_ text: String) async -> String? {
        do {
            if kokoro == nil {
                let manager = KokoroAneManager()
                // First run downloads the CoreML chain from HuggingFace.
                try await manager.initialize()
                kokoro = manager
            }
            guard let kokoro else { return "Voice model failed to load." }
            let voice = SettingsStore.shared.ttsKokoroVoice
            let wav = try await kokoro.synthesize(
                text: text, voice: voice.isEmpty ? nil : voice
            )
            return play(wav)
        } catch {
            log.error("kokoro synth failed: \(error, privacy: .public)")
            return "Kokoro synthesis failed. Check the voice name in Settings."
        }
    }

    private func speakViaServer(_ text: String) async -> String? {
        let engine = SettingsStore.shared.ttsEngine
        let voice = switch engine {
        case .qwen: SettingsStore.shared.ttsQwenVoice
        case .kokoroServer: SettingsStore.shared.ttsKokoroVoice
        default: ""
        }
        guard let request = TtsRequestBuilder.speechRequest(
            engine: engine, text: text, voice: voice
        ) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                log.error("tts server status \(status): \(String(data: data.prefix(200), encoding: .utf8) ?? "", privacy: .public)")
                return "Voice server error (\(status)). First use downloads the model; try again."
            }
            return play(data)
        } catch {
            return "Voice server not running. Start it with `make tts-serve`."
        }
    }

    private func play(_ audio: Data) -> String? {
        do {
            let player = try AVAudioPlayer(data: audio)
            self.player = player
            player.play()
            return nil
        } catch {
            log.error("playback failed: \(error, privacy: .public)")
            return "Could not play the synthesized audio."
        }
    }
}
