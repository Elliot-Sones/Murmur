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

    /// Cleanup may only remove or fix words, so nearly every output word must
    /// come from the transcript. A low ratio means the model answered or
    /// invented instead of cleaning.
    private static func isOffScript(_ output: String, rawTranscript: String) -> Bool {
        let spokenWords = Set(WordErrorRate.normalize(rawTranscript))
        let outputWords = WordErrorRate.normalize(output)
        guard !spokenWords.isEmpty, !outputWords.isEmpty else { return false }
        let kept = outputWords.filter { spokenWords.contains($0) }.count
        return Double(kept) / Double(outputWords.count) < 0.6
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
