import AVFoundation
import FluidAudio
import Foundation

/// Parakeet TDT 0.6B v2 (English) on CoreML via FluidAudio.
///
/// Two paths share the same loaded models:
/// - Batch `transcribe` for the HUD preview and as fallback.
/// - A per-utterance `SlidingWindowAsrManager` session that transcribes
///   11 s windows while audio is still being fed, so `finishStream` only
///   pays for the final partial window instead of the whole utterance.
actor FluidAudioTranscriber: TranscriptionService {
    private var manager: AsrManager?
    private var models: AsrModels?
    private var window: SlidingWindowAsrManager?
    private var windowFedSamples = 0

    private static let streamFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!

    var isReady: Bool { manager != nil }

    func prepare(progress: @escaping @Sendable (String) -> Void) async throws {
        guard manager == nil else { return }
        progress("Downloading speech model…")
        let models = try await AsrModels.downloadAndLoad(version: .v2)
        progress("Loading speech model…")
        let loaded = AsrManager(config: .default)
        try await loaded.loadModels(models)
        self.models = models
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

    /// A sliding-window session is single-use: its input stream cannot be
    /// restarted after finish/cancel, so each utterance gets a fresh manager.
    /// The CoreML models are shared by reference, so this is cheap.
    func beginStream() async {
        guard let models, window == nil else { return }
        let session = SlidingWindowAsrManager()
        do {
            try await session.loadModels(models)
            try await session.startStreaming(source: .microphone)
            window = session
            windowFedSamples = 0
        } catch {
            // Leave window nil; finishStream falls back to batch.
        }
    }

    func streamSamples(_ allSamples: [Float]) async {
        guard let window, allSamples.count > windowFedSamples else { return }
        guard let buffer = Self.pcmBuffer(from: Array(allSamples[windowFedSamples...])) else { return }
        windowFedSamples = allSamples.count
        await window.streamAudio(buffer)
    }

    func finishStream(_ allSamples: [Float]) async throws -> String {
        guard let window else { return try await transcribe(allSamples) }
        // Nil out before the first await so a late streamSamples from the
        // feed loop cannot inject audio into a finishing session.
        self.window = nil
        if allSamples.count > windowFedSamples,
            let buffer = Self.pcmBuffer(from: Array(allSamples[windowFedSamples...])) {
            await window.streamAudio(buffer)
        }
        windowFedSamples = 0
        do {
            let text = try await window.finish()
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // Every window failed; one batch pass still saves the dictation.
            return try await transcribe(allSamples)
        }
    }

    func abortStream() async {
        guard let window else { return }
        self.window = nil
        windowFedSamples = 0
        await window.cancel()
    }

    private static func pcmBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: streamFormat, frameCapacity: AVAudioFrameCount(samples.count)
            )
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress, let channel = buffer.floatChannelData else { return }
            channel[0].update(from: base, count: samples.count)
        }
        return buffer
    }
}
