import Foundation

@main struct PullRequestSummaryCheck {
    static func parse(_ json: String) -> PullRequestSummary? { PullRequestSummary.parse(Data(json.utf8)) }
    static func main() {
        let failing = parse(#"{"number":42,"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"","statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"}],"url":"https://github.com/o/r/pull/42"}"#)!
        precondition(failing.number == 42 && failing.checks == .failing && failing.reviewDecision == nil && failing.needsAttention)
        precondition(failing.summary == "Pull request #42, checks failing.")
        let pending = parse(#"{"number":7,"state":"OPEN","isDraft":true,"mergeable":"UNKNOWN","reviewDecision":"REVIEW_REQUIRED","statusCheckRollup":[{"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":""},{"__typename":"StatusContext","state":"SUCCESS"}]}"#)!
        precondition(pending.checks == .pending && pending.isDraft && !pending.needsAttention)
        precondition(pending.summary == "Pull request #7 (draft), checks running, review required.")
        let good = parse(#"{"number":8,"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","reviewDecision":"APPROVED","statusCheckRollup":[{"__typename":"StatusContext","state":"SUCCESS"}]}"#)!
        precondition(good.checks == .passing && !good.needsAttention && good.summary == "Pull request #8, checks passing, approved.")
        let conflict = parse(#"{"number":9,"state":"OPEN","isDraft":false,"mergeable":"CONFLICTING","reviewDecision":"CHANGES_REQUESTED","statusCheckRollup":[]}"#)!
        precondition(conflict.checks == .none && conflict.needsAttention && conflict.summary == "Pull request #9, has merge conflicts, changes requested.")
        let merged = parse(#"{"number":3,"state":"MERGED","isDraft":false,"mergeable":"UNKNOWN","reviewDecision":"APPROVED","statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"}]}"#)!
        precondition(merged.state == .merged && !merged.needsAttention && merged.summary == "Pull request #3 is merged.")
        precondition(parse("not json") == nil && parse(#"{"number":1,"state":"WEIRD"}"#) == nil)
        precondition(PullRequestSummary.isNoPullRequest("no pull requests found for branch \"x\""))
        precondition(!PullRequestSummary.isNoPullRequest("error connecting to api.github.com"))
        let now = Date(timeIntervalSince1970: 10_000)
        let trees = [(path: "/a", branch: "a"), (path: "/b", branch: "b"), (path: "/c", branch: "detached HEAD"), (path: "/d", branch: "d")]
        let checked = ["/a": now.addingTimeInterval(-10), "/b": now.addingTimeInterval(-400)]
        precondition(PullRequestSummary.due(trees, checked: checked, now: now, interval: 300, limit: 5) == ["/d", "/b"])
        precondition(PullRequestSummary.due(trees, checked: checked, now: now, interval: 300, limit: 1) == ["/d"])
        print("PASS: pull request summaries (checks, review, conflicts, merged, lookup schedule)")
    }
}
