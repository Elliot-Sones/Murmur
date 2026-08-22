import Foundation
import NaturalLanguage

/// Splits reader text into speakable sentences. Newlines always break
/// (list items rarely end with punctuation); NLTokenizer handles the rest
/// so abbreviations like "Dr." don't over-split.
enum SentenceSplitter {
    static func split(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).flatMap(splitLine)
    }

    /// Halves time-to-first-audio for long openers: a first sentence past
    /// the threshold is split at its first clause boundary (comma/semicolon/
    /// colon) so a short head synthesizes fast while the tail follows.
    static func fastStart(_ sentences: [String], threshold: Int = 60) -> [String] {
        guard let first = sentences.first, first.count > threshold else { return sentences }
        // A boundary before this sounds choppy rather than fast.
        let minimumHead = 20
        let boundaries: Set<Character> = [",", ";", ":"]
        guard let cut = first.indices.first(where: { index in
            boundaries.contains(first[index])
                && first.distance(from: first.startIndex, to: index) >= minimumHead
        }) else { return sentences }
        let head = String(first[...cut])
        let tail = String(first[first.index(after: cut)...])
            .trimmingCharacters(in: .whitespaces)
        guard !tail.isEmpty else { return sentences }
        return [head, tail] + sentences.dropFirst()
    }

    private static func splitLine(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let sentence = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        return sentences
    }
}

/// Playback speed steps for the reader bar, applied through the time-pitch
/// unit (AVAudioPlayer.rate would cap at 2x).
enum ReaderSpeed {
    static let steps: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    static func next(after speed: Double) -> Double {
        guard let current = steps.firstIndex(where: { abs($0 - speed) < 0.001 }),
            current + 1 < steps.count
        else { return steps[0] }
        return steps[current + 1]
    }

    static func label(for speed: Double) -> String {
        speed == speed.rounded()
            ? "\(Int(speed))×"
            : "\(speed.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}
