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
}
