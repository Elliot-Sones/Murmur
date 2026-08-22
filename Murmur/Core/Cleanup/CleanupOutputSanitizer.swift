import Foundation

/// Strips assistant chatter from model output: preamble lines like
/// "Sure, here's a polished version of your text:", wrapping quotes, and code
/// fences. Guarded so it never removes words the user actually spoke.
enum CleanupOutputSanitizer {
    private static let preambleStarters = [
        "sure", "okay", "of course", "certainly", "absolutely", "got it",
        "here is", "here's", "here are", "below is", "the following",
    ]
    private static let preambleHints = [
        "version", "cleaned", "rewritten", "polished", "transcript", "revised", "updated text",
    ]

    static func sanitize(
        _ output: String, rawTranscript: String, enforceWordOverlap: Bool = true
    ) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        text = stripCodeFences(text)
        text = stripPreambleLine(text, rawTranscript: rawTranscript)
        if enforceWordOverlap {
            text = stripEchoLines(text, rawTranscript: rawTranscript)
        }
        text = stripWrappingQuotes(text)
        if enforceWordOverlap {
            // ASR never produces literal prompt delimiters; only an echoing
            // model does. Rewrite selections may contain them legitimately.
            text = text
                .replacingOccurrences(of: "<transcript>", with: "")
                .replacingOccurrences(of: "</transcript>", with: "")
        }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return rawTranscript }
        if enforceWordOverlap, isOffScript(result, rawTranscript: rawTranscript) {
            return rawTranscript
        }
        return result
    }

    /// Cleanup may only remove fillers or fix words. Three independent
    /// checks: nearly every output word must come from the transcript, the
    /// output must not be meaningfully longer than what was spoken (an
    /// answer that quotes the question passes the first check but never
    /// this one), and it must not be meaningfully shorter either (a summary
    /// is built entirely from the speaker's own words, so only a length
    /// floor catches it).
    private static func isOffScript(_ output: String, rawTranscript: String) -> Bool {
        let spoken = WordErrorRate.normalize(rawTranscript)
        let outputWords = WordErrorRate.normalize(output)
        guard !spoken.isEmpty, !outputWords.isEmpty else { return false }

        let spokenSet = Set(spoken)
        let kept = outputWords.filter { spokenSet.contains($0) }.count
        if Double(kept) / Double(outputWords.count) < 0.6 { return true }

        let allowedLength = Int(Double(spoken.count) * 1.3) + 2
        if outputWords.count > allowedLength { return true }

        // Filler removal drops a handful of words; summarizing drops far
        // more. Past the allowance, keep the speaker's full words instead.
        let dropped = Double(spoken.count - outputWords.count)
        return dropped > max(3, Double(spoken.count) * 0.3)
    }

    private static func stripCodeFences(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.count >= 2,
            lines.first?.hasPrefix("```") == true,
            lines.last?.hasPrefix("```") == true
        else { return text }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n")
    }

    /// Drops lines whose words the user mostly never spoke; the model once
    /// recited the personal dictionary as an appended sentence, short enough
    /// to slip past the whole-output overlap and length guards. Lines of
    /// three or fewer words are kept: formatted list items ("1. Eggs") share
    /// too few literal words with speech ("first eggs") to judge fairly.
    private static func stripEchoLines(_ text: String, rawTranscript: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }
        let spokenWords = Set(WordErrorRate.normalize(rawTranscript))
        return lines.filter { line in
            let words = WordErrorRate.normalize(line)
            guard words.count > 3 else { return true }
            let overlap = words.filter { spokenWords.contains($0) }.count
            return Double(overlap) / Double(words.count) >= 0.6
        }
        .joined(separator: "\n")
    }

    private static func stripPreambleLine(_ text: String, rawTranscript: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let first = lines[0].trimmingCharacters(in: .whitespaces)
        guard first.hasSuffix(":") else { return text }
        let lowered = first.lowercased()
        let looksLikePreamble = preambleStarters.contains { lowered.hasPrefix($0) }
            || preambleHints.contains { lowered.contains($0) }
        guard looksLikePreamble else { return text }

        // Keep the line when it is mostly words the user actually spoke.
        let spokenWords = Set(WordErrorRate.normalize(rawTranscript))
        let lineWords = WordErrorRate.normalize(first)
        if !lineWords.isEmpty {
            let overlap = lineWords.filter { spokenWords.contains($0) }.count
            if Double(overlap) / Double(lineWords.count) > 0.6 { return text }
        }
        return lines.dropFirst().joined(separator: "\n")
    }

    private static func stripWrappingQuotes(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”")]
        for (opening, closing) in pairs {
            if trimmed.count > 2, trimmed.first == opening, trimmed.last == closing {
                return String(trimmed.dropFirst().dropLast())
            }
        }
        return trimmed
    }
}
