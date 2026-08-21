import Foundation

/// Fractions of a whole for the history timing bar.
enum StageShare {
    /// Each value's fraction of the total. All zeros when the total is 0;
    /// negative inputs count as 0.
    static func shares(_ values: [Int]) -> [Double] {
        let clamped = values.map { max(0, $0) }
        let total = clamped.reduce(0, +)
        guard total > 0 else { return clamped.map { _ in 0 } }
        return clamped.map { Double($0) / Double(total) }
    }
}
