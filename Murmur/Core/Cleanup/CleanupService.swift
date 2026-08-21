import Foundation

@MainActor
protocol CleanupService: AnyObject {
    /// Returns cleaned text, or the raw transcript unchanged on any failure. Never throws.
    func cleanup(_ raw: String) async -> String
}

@MainActor
final class RawPassthroughCleanup: CleanupService {
    func cleanup(_ raw: String) async -> String { raw }
}
