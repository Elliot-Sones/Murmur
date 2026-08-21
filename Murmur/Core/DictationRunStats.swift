import Foundation

/// Per-stage timing for the last completed dictation, shown in the menu bar.
struct DictationRunStats: Equatable {
    var audioMs: Int
    var transcribeMs: Int
    var cleanupMs: Int
    var pasteMs: Int
    var characters: Int
    var engine: String

    /// Time from key release until the paste keystroke was sent.
    var totalMs: Int { transcribeMs + cleanupMs + pasteMs }

    var audioSummary: String {
        String(format: "%.1f s audio → %d chars in %d ms", Double(audioMs) / 1000, characters, totalMs)
    }

    var stageSummary: String {
        "ASR \(transcribeMs) ms · Cleanup \(cleanupMs) ms · Paste \(pasteMs) ms"
    }
}
