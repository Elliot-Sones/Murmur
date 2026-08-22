import Foundation

/// Decides when a clipboard change means "the user copied text they want
/// read" while the pill is on. Only fires for copies made where AX cannot
/// see a selection (Warp with a TUI) but the focused element is still
/// text-like, so file copies in Finder stay silent. Pure state; the
/// pasteboard, AX reads, and audio live elsewhere.
struct ClipboardWatchLogic {
    private var lastCount: Int?
    private var ignored: Set<Int> = []

    /// Marks a change count as Murmur's own write (paste, snapshot restore).
    mutating func ignore(changeCount: Int) {
        ignored.insert(changeCount)
    }

    /// Feed one poll; true means "speak the clipboard now".
    mutating func observe(
        changeCount: Int, axSeesSelection: Bool, focusedRoleIsTexty: Bool
    ) -> Bool {
        defer { ignored.remove(changeCount) }
        guard let baseline = lastCount else {
            lastCount = changeCount
            return false
        }
        guard changeCount != baseline else { return false }
        lastCount = changeCount
        if ignored.contains(changeCount) { return false }
        return !axSeesSelection && focusedRoleIsTexty
    }
}
