import Foundation

enum TranscriberError: Error {
    case notReady
}

protocol TranscriptionService: Sendable {
    /// Downloads and loads models if needed. Safe to call more than once.
    func prepare(progress: @escaping @Sendable (String) -> Void) async throws
    var isReady: Bool { get async }
    /// Samples must be 16 kHz mono Float32.
    func transcribe(_ samples: [Float]) async throws -> String

    /// Optional streaming session: audio fed while recording is transcribed
    /// incrementally, so finishing only pays for the un-processed tail instead
    /// of the whole utterance. Callers pass the full accumulated sample buffer
    /// each time; the implementation feeds only what it has not seen yet.
    func beginStream() async
    func streamSamples(_ allSamples: [Float]) async
    func finishStream(_ allSamples: [Float]) async throws -> String
    func abortStream() async
    /// Text accumulated so far by an active streaming session, nil if none.
    func streamingPreviewText() async -> String?
}

/// Engines without streaming support transparently fall back to batch.
extension TranscriptionService {
    func beginStream() async {}
    func streamSamples(_ allSamples: [Float]) async {}
    func finishStream(_ allSamples: [Float]) async throws -> String {
        try await transcribe(allSamples)
    }
    func abortStream() async {}
    func streamingPreviewText() async -> String? { nil }
}
