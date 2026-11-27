import Foundation

@main struct AttentionAlertsCheck {
    static func main() {
        let a = "/repo/a", b = "/repo/b", c = "/repo/c"
        // Only new arrivals alert, in a stable order.
        precondition(AttentionAlerts.newlyWaiting(previous: [], current: [b, a], muted: [], focused: nil) == [a, b])
        precondition(AttentionAlerts.newlyWaiting(previous: [a], current: [a, b], muted: [], focused: nil) == [b])
        // Still waiting: no repeat alert.
        precondition(AttentionAlerts.newlyWaiting(previous: [a, b], current: [a, b], muted: [], focused: nil).isEmpty)
        // Muted and focused worktrees never alert.
        precondition(AttentionAlerts.newlyWaiting(previous: [], current: [a, b, c], muted: [b], focused: c) == [a])
        // Waiting again after being answered alerts again.
        precondition(AttentionAlerts.newlyWaiting(previous: [], current: [a], muted: [], focused: nil) == [a])
        precondition(AttentionAlerts.badge(waiting: [], muted: []) == nil)
        precondition(AttentionAlerts.badge(waiting: [a, b, c], muted: [b]) == "2")
        precondition(AttentionAlerts.badge(waiting: [a], muted: [a]) == nil)
        print("PASS: attention alerts (arrivals, repeats, mute, focus, badge)")
    }
}
