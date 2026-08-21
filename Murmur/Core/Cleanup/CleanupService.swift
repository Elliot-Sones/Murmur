import Foundation

/// What the cleanup model should know beyond the transcript itself.
struct CleanupContext: Equatable {
    var dictionary: [String] = []
    var toneHint: String?
}

@MainActor
protocol CleanupService: AnyObject {
    /// Returns cleaned text, or the raw transcript unchanged on any failure. Never throws.
    func cleanup(_ raw: String, context: CleanupContext) async -> String
}

@MainActor
final class RawPassthroughCleanup: CleanupService {
    func cleanup(_ raw: String, context: CleanupContext) async -> String { raw }
}
