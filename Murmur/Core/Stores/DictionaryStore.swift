import Foundation
import Observation

/// Personal dictionary: words the cleanup model should prefer (names, jargon).
/// Persisted as JSON under Application Support/Murmur.
@MainActor
@Observable
final class DictionaryStore {
    static let shared = DictionaryStore(directory: murmurApplicationSupportDirectory())

    private(set) var words: [String] = []
    @ObservationIgnored private let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("dictionary.json")
        dismissedURL = directory.appendingPathComponent("dismissed-suggestions.json")
        words = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: fileURL))) ?? []
        dismissedSuggestions =
            (try? JSONDecoder().decode([String].self, from: Data(contentsOf: dismissedURL))) ?? []
    }

    func add(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !words.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return
        }
        words.append(trimmed)
        persist()
    }

    func remove(_ word: String) {
        words.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
        persist()
    }

    private(set) var dismissedSuggestions: [String] = []
    @ObservationIgnored private let dismissedURL: URL

    func dismissSuggestion(_ word: String) {
        guard !dismissedSuggestions.contains(where: {
            $0.caseInsensitiveCompare(word) == .orderedSame
        }) else { return }
        dismissedSuggestions.append(word)
        try? FileManager.default.createDirectory(
            at: dismissedURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(dismissedSuggestions) {
            try? data.write(to: dismissedURL, options: [.atomic])
        }
    }

    private func persist() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(words) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}

func murmurApplicationSupportDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Murmur", isDirectory: true)
}
