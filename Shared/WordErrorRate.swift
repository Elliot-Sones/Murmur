import Foundation

/// Word error rate between a reference transcript and a hypothesis.
/// Shared by the app target and the murmur-bench tool.
enum WordErrorRate {
    /// Lowercases, strips punctuation, splits on whitespace.
    /// Word-internal apostrophes survive ("it's") because they sit between
    /// letters and are part of how people actually speak.
    static func normalize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { word in
                String(word.unicodeScalars.filter { scalar in
                    CharacterSet.alphanumerics.contains(scalar) || scalar == "'"
                })
                .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            }
            .filter { !$0.isEmpty }
    }

    /// Word-level Levenshtein distance divided by reference length.
    /// An empty reference gives 0 for an empty hypothesis, otherwise the
    /// hypothesis word count (all insertions).
    static func compute(reference: String, hypothesis: String) -> Double {
        let ref = normalize(reference)
        let hyp = normalize(hypothesis)
        guard !ref.isEmpty else { return Double(hyp.count) }
        guard !hyp.isEmpty else { return 1 }

        var previous = Array(0...hyp.count)
        var current = [Int](repeating: 0, count: hyp.count + 1)
        for i in 1...ref.count {
            current[0] = i
            for j in 1...hyp.count {
                let substitution = previous[j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return Double(previous[hyp.count]) / Double(ref.count)
    }
}
