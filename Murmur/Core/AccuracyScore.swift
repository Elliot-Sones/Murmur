import Foundation

/// Accuracy of an inserted dictation against the user's hand correction.
enum AccuracyScore {
    /// 0...100 percent. The correction is ground truth.
    static func percent(inserted: String, corrected: String) -> Double {
        let wer = WordErrorRate.compute(reference: corrected, hypothesis: inserted)
        return max(0, 1 - wer) * 100
    }
}

enum Median {
    static func of(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
