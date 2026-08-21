import Foundation

/// What review mode learned from the user's accept.
enum ReviewOutcome {
    /// The ground-truth correction: nil when the user inserted the model's
    /// text unchanged, the final text when they edited it first.
    static func correction(model: String, final: String) -> String? {
        let trimmedFinal = final.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFinal.isEmpty, trimmedFinal != trimmedModel else { return nil }
        return trimmedFinal
    }
}
