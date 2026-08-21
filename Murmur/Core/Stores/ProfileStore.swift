import Foundation
import Observation

/// Per-app dictation behavior, matched by bundle identifier.
struct AppProfile: Codable, Equatable, Identifiable {
    var bundleId: String
    var appName: String = ""
    var toneHint: String?
    var rawMode = false
    var vocab: [String] = []

    var id: String { bundleId }
}

/// Persists app profiles as JSON under Application Support/Murmur.
@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore(directory: murmurApplicationSupportDirectory())

    private(set) var profiles: [AppProfile] = []
    @ObservationIgnored private let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("profiles.json")
        profiles = (try? JSONDecoder().decode([AppProfile].self, from: Data(contentsOf: fileURL))) ?? []
    }

    /// Adds or replaces the profile with the same bundle id.
    func upsert(_ profile: AppProfile) {
        profiles.removeAll { $0.bundleId.caseInsensitiveCompare(profile.bundleId) == .orderedSame }
        profiles.append(profile)
        persist()
    }

    func remove(bundleId: String) {
        profiles.removeAll { $0.bundleId.caseInsensitiveCompare(bundleId) == .orderedSame }
        persist()
    }

    func resolve(bundleId: String?) -> AppProfile? {
        guard let bundleId else { return nil }
        return profiles.first { $0.bundleId.caseInsensitiveCompare(bundleId) == .orderedSame }
    }

    private func persist() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}
