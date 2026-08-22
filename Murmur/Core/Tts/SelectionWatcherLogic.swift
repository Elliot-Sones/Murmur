import Foundation

/// Decides when a polled text selection is stable enough to speak.
/// Pure state; the timer, AX reads, and audio live elsewhere.
///
/// A selection speaks when the same non-empty text is seen on two
/// consecutive polls (the drag has settled) and it was not the last thing
/// spoken. Clearing the selection re-arms everything, so highlighting the
/// same passage again speaks it again.
struct SelectionWatcherLogic {
    /// Generous: the sentence pipeline reads long articles fine.
    static let maxCharacters = 5000

    private var pending: String?
    private var lastSpoken: String?

    /// One-shot settle signal (mouse release): speak now if non-empty and
    /// not already spoken, no two-poll stability needed.
    mutating func settle(_ selection: String?) -> String? {
        let text = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, text != lastSpoken else { return nil }
        pending = nil
        lastSpoken = text
        return String(text.prefix(Self.maxCharacters))
    }

    /// Feed one poll's selection; returns text to speak, or nil.
    mutating func observe(_ selection: String?) -> String? {
        let text = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            pending = nil
            lastSpoken = nil
            return nil
        }
        if text == lastSpoken { return nil }
        guard text == pending else {
            pending = text
            return nil
        }
        pending = nil
        lastSpoken = text
        return String(text.prefix(Self.maxCharacters))
    }
}
