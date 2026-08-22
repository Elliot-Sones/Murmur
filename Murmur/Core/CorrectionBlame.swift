import Foundation

/// Heuristic attribution for a corrected dictation: which stage most likely
/// caused the gap between what was inserted and what the user wanted.
/// Compares word error rates of the raw transcript and the cleaned output
/// against the user's correction.
enum CorrectionBlame: Equatable {
    /// The cleanup model changed or added words the user never spoke.
    case cleanup
    /// The recognizer misheard; cleanup faithfully kept the mistake.
    case transcription
    /// The user rewrote freely; not a model error.
    case rephrased
    /// Only punctuation or casing differed.
    case formatting

    /// Above this error against BOTH raw and cleaned, the user was writing a
    /// different sentence, not fixing this one.
    private static let rephraseThreshold = 0.5
    /// Cleanup must be meaningfully worse than raw before it takes the blame.
    private static let epsilon = 0.05

    static func classify(raw: String, cleaned: String, corrected: String) -> CorrectionBlame {
        let cleanedError = WordErrorRate.compute(reference: corrected, hypothesis: cleaned)
        let rawError = WordErrorRate.compute(reference: corrected, hypothesis: raw)
        if cleanedError == 0 { return .formatting }
        if cleanedError >= rephraseThreshold, rawError >= rephraseThreshold { return .rephrased }
        if cleanedError > rawError + epsilon { return .cleanup }
        return .transcription
    }

    var explanation: String {
        switch self {
        case .cleanup: "Likely cause: AI cleanup changed or added words"
        case .transcription: "Likely cause: speech recognition misheard"
        case .rephrased: "You rephrased it; not counted as a model error"
        case .formatting: "Punctuation or casing only"
        }
    }
}
