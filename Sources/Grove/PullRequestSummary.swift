import Foundation

/// What the sidebar shows about a worktree's pull request, parsed from
/// `gh pr view --json` output. Kept in memory only; never persisted.
struct PullRequestSummary: Equatable, Sendable {
    enum State: String, Sendable { case open = "OPEN", merged = "MERGED", closed = "CLOSED" }
    enum Checks: Equatable, Sendable { case none, pending, passing, failing }
    let number: Int
    let state: State
    let isDraft: Bool
    let checks: Checks
    /// "APPROVED", "CHANGES_REQUESTED", "REVIEW_REQUIRED" or nil.
    let reviewDecision: String?
    /// "CONFLICTING" when the branch cannot merge cleanly.
    let mergeable: String?
    let url: String?

    static let fields = "number,state,isDraft,mergeable,reviewDecision,statusCheckRollup,url"

    static func parse(_ data: Data) -> PullRequestSummary? {
        guard let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = values["number"] as? Int,
              let state = (values["state"] as? String).flatMap(State.init(rawValue:)) else { return nil }
        let review = (values["reviewDecision"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return PullRequestSummary(number: number, state: state, isDraft: values["isDraft"] as? Bool ?? false,
                                  checks: checks(values["statusCheckRollup"] as? [[String: Any]] ?? []),
                                  reviewDecision: review, mergeable: values["mergeable"] as? String, url: values["url"] as? String)
    }

    /// CheckRun entries carry status/conclusion; StatusContext entries carry state.
    static func checks(_ rollup: [[String: Any]]) -> Checks {
        guard !rollup.isEmpty else { return .none }
        let failed: Set<String> = ["FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"]
        var pending = false
        for check in rollup {
            let conclusion = (check["conclusion"] as? String ?? "").uppercased()
            let state = (check["state"] as? String ?? "").uppercased()
            if failed.contains(conclusion) || failed.contains(state) { return .failing }
            if let status = check["status"] as? String, status.uppercased() != "COMPLETED" { pending = true }
            if state == "PENDING" || state == "EXPECTED" { pending = true }
        }
        return pending ? .pending : .passing
    }

    /// Whether the badge should stand out: something needs the author.
    var needsAttention: Bool {
        state == .open && (checks == .failing || mergeable == "CONFLICTING" || reviewDecision == "CHANGES_REQUESTED")
    }

    /// One plain sentence for tooltips and VoiceOver.
    var summary: String {
        switch state {
        case .merged: return "Pull request #\(number) is merged."
        case .closed: return "Pull request #\(number) is closed."
        case .open:
            var parts = ["Pull request #\(number)" + (isDraft ? " (draft)" : "")]
            switch checks {
            case .failing: parts.append("checks failing")
            case .pending: parts.append("checks running")
            case .passing: parts.append("checks passing")
            case .none: break
            }
            if mergeable == "CONFLICTING" { parts.append("has merge conflicts") }
            switch reviewDecision {
            case "APPROVED": parts.append("approved")
            case "CHANGES_REQUESTED": parts.append("changes requested")
            case "REVIEW_REQUIRED": parts.append("review required")
            default: break
            }
            return parts.joined(separator: ", ") + "."
        }
    }

    /// `gh pr view` exits non-zero both for "no pull request" and for real
    /// failures; only the first means the worktree has none.
    static func isNoPullRequest(_ output: String) -> Bool {
        output.lowercased().contains("no pull requests found")
    }

    /// Worktrees to look up now: named branches not checked within
    /// `interval` seconds, oldest first (never-checked first), at most `limit`.
    static func due(_ worktrees: [(path: String, branch: String)], checked: [String: Date], now: Date, interval: TimeInterval, limit: Int) -> [String] {
        worktrees.filter { $0.branch != "detached HEAD" && (checked[$0.path].map { now.timeIntervalSince($0) >= interval } ?? true) }
            .sorted { (checked[$0.path] ?? .distantPast) < (checked[$1.path] ?? .distantPast) }
            .prefix(limit).map(\.path)
    }
}
