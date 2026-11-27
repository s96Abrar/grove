import Foundation

/// Which worktrees deserve a notification. Pure set logic, so it can be
/// checked without a GUI: a worktree alerts once when it starts waiting,
/// unless it is muted or is the worktree the user is already looking at.
enum AttentionAlerts {
    /// `previous` and `current` are the worktree paths whose stable status is
    /// "awaiting input" in consecutive status samples. `focused` is the
    /// selected worktree while Grove is the active app, otherwise nil.
    static func newlyWaiting(previous: Set<String>, current: Set<String>, muted: Set<String>, focused: String?) -> [String] {
        current.subtracting(previous).subtracting(muted).filter { $0 != focused }.sorted()
    }
    /// Dock badge text: the number of unmuted waiting worktrees, or nil.
    static func badge(waiting: Set<String>, muted: Set<String>) -> String? {
        let count = waiting.subtracting(muted).count
        return count > 0 ? String(count) : nil
    }
}
