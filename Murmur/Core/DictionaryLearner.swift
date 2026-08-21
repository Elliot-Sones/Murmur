import Foundation

/// Finds proper nouns and unusual words that keep appearing in dictation
/// history and are not yet in the dictionary.
enum DictionaryLearner {
    private static let stopWords: Set<String> = {
        var words: Set<String> = ["i", "i'm", "i'll", "i've", "i'd", "ok", "okay"]
        words.formUnion([
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        ])
        words.formUnion([
            "january", "february", "march", "april", "may", "june", "july",
            "august", "september", "october", "november", "december",
        ])
        return words
    }()

    static func suggestions(
        from texts: [String],
        knownWords: [String],
        minOccurrences: Int = 3
    ) -> [String] {
        let known = Set(knownWords.map { $0.lowercased() })
        var counts: [String: Int] = [:]

        for text in texts {
            let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            for sentence in sentences {
                let tokens = sentence
                    .components(separatedBy: .whitespaces)
                    .map(trimPunctuation)
                    .filter { !$0.isEmpty }
                for (index, token) in tokens.enumerated() {
                    guard isCandidate(token, sentenceInitial: index == 0) else { continue }
                    guard !stopWords.contains(token.lowercased()) else { continue }
                    guard !known.contains(token.lowercased()) else { continue }
                    counts[token, default: 0] += 1
                }
            }
        }

        return counts
            .filter { $0.value >= minOccurrences }
            .sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .map(\.key)
    }

    private static func trimPunctuation(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private static func isCandidate(_ token: String, sentenceInitial: Bool) -> Bool {
        guard token.count >= 2, let first = token.first else { return false }
        let hasInternalCapital = token.dropFirst().contains { $0.isUppercase }
        if hasInternalCapital { return true }
        return first.isUppercase && !sentenceInitial
    }
}
