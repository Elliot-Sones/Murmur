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
    /// FluidAudio recycles MLMultiArrays through one global cache shared by
    /// every ASR engine instance, and returning an array zeroes memory another
    /// in-flight prediction may still read (observed as libmalloc free-block
    /// corruption). Batch passes and stream finishes therefore take turns
    /// through this slot; window-chunk processing during recording is kept
    /// exclusive by the preview cutoff in DictationController instead.
    private var inference: Task<String, any Error>?

    private func withInferenceSlot(
        _ body: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        while let running = inference { _ = try? await running.value }
        let task = Task { try await body() }
        inference = task
        defer { inference = nil }
        return try await task.value
    }

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
        return try await withInferenceSlot {
            // Fresh decoder state per utterance; dictations are independent.
            var decoderState = try TdtDecoderState()
            let result = try await manager.transcribe(samples, decoderState: &decoderState)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Accumulated text of the active streaming session (confirmed windows
    /// plus the volatile tail), for the HUD once batch previews must stop.
    func streamingPreviewText() async -> String? {
        guard let window else { return nil }
        let confirmed = await window.confirmedTranscript
        let volatile = await window.volatileTranscript
        let joined = [confirmed, volatile].filter { !$0.isEmpty }.joined(separator: " ")
        return joined.isEmpty ? nil : joined
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
        guard let manager else { throw TranscriberError.notReady }
        // Nil out before the first await so a late streamSamples from the
        // feed loop cannot inject audio into a finishing session.
        self.window = nil
        let tail = allSamples.count > windowFedSamples ? Array(allSamples[windowFedSamples...]) : []
        windowFedSamples = 0
        return try await withInferenceSlot {
            if let buffer = Self.pcmBuffer(from: tail) {
                await window.streamAudio(buffer)
            }
            do {
                let text = try await window.finish()
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                // Every window failed; one batch pass still saves the dictation.
                var decoderState = try TdtDecoderState()
                let result = try await manager.transcribe(allSamples, decoderState: &decoderState)
                return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
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
