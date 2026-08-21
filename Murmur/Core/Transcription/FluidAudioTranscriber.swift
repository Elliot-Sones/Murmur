import FluidAudio
import Foundation

/// Parakeet TDT 0.6B v2 (English) on CoreML via FluidAudio.
actor FluidAudioTranscriber: TranscriptionService {
    private var manager: AsrManager?

    var isReady: Bool { manager != nil }

    func prepare(progress: @escaping @Sendable (String) -> Void) async throws {
        guard manager == nil else { return }
        progress("Downloading speech model…")
        let models = try await AsrModels.downloadAndLoad(version: .v2)
        progress("Loading speech model…")
        let loaded = AsrManager(config: .default)
        try await loaded.loadModels(models)
        manager = loaded
        progress("Ready")
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager else { throw TranscriberError.notReady }
        // Fresh decoder state per utterance; dictations are independent.
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
