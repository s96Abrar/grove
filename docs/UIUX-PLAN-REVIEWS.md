# Grove — Council Review of `docs/UIUX-PLAN.md`

**Panel:** 4 reviewers (Staff AppKit/focus specialist, Staff performance/systems engineer, Principal macOS Product Designer, adversarial safety/regression reviewer). All reviewed the plan, the audit (`docs/UIUX-AUDIT.md`), and the actual source. **Overall: APPROVE-WITH-CHANGES (4×).** All blocking change requests below are folded into plan §8 and applied before implementation.

## Verdicts

| Reviewer | Verdict | Blocking items |
|---|---|---|
| AppKit/focus specialist | APPROVE-WITH-CHANGES | 4 |
| Performance/systems | APPROVE-WITH-CHANGES | 4 |
| Product/UX principal | APPROVE-WITH-CHANGES | 6 |
| Safety/regression (adversarial) | APPROVE-WITH-CHANGES | 5 |

## Blocking change requests (consolidated)

### Focus & keyboard (AppKit reviewer)
1. **§2.1:** `TerminalPane` is SwiftUI with no first-responder event hook — "record on becoming first responder" has no trigger. Fix: snapshot the focused pane *before presenting* each sheet/alert (at the `creating`/`deleting`/`closing`/palette sites, using the `Workspace.swift:98` predicate); optional continuous tracking via subclassing `LocalProcessTerminalView` in `EmbeddedTerminal.makeNSView` (`becomeFirstResponder`/`resignFirstResponder` overrides). Keep onDismiss + async re-focus with guards (session exists, `view.window != nil`, check `makeFirstResponder` return).
2. **§2.3:** `.onMoveCommand` never fires while the query `TextField` is first responder. Fix: `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` scoped to the palette sheet, intercepting Up/Down to move `selection`; Return executes the selected row (replace `executeFirst()`).
3. **§5.3:** `.keyboardShortcut` inside `.alert` is discarded on macOS (NSAlert-backed). Fix: custom sheet-hosted dialog (pattern exists at `Grove.swift:241-243`) where ⌘Return/`.cancelAction` work, or `NSAlert` with `keyEquivalent = "\r"`.
4. **§2.5:** the `isKey` predicate in `body` has no invalidation trigger; also misnamed (tests first responder, not key window). Fix: derive the accent border from the published focus state (item 1's mechanism) + `window.isKeyWindow`.

### Performance & systems
5. **§4.2:** `Worktree` value types are regenerated every poll — diff stats stored on them are lost each cycle. Fix: separate `@Published var diffStats: [String: DiffSummary]` in `Workspace` keyed by path; share the `refreshing` guard; route failures to the §2.2 banner.
6. **§4.2:** 5 s status+numstat across 30 worktrees ≈ 720 git spawns/min — too hot for Efficient. Fix (tier-gated): HighPerformance 5 s with numstat only for non-clean trees; Efficient 10–15 s status-only; skip cycles while window not key; sequential within one detached task.
7. **§3.4:** apps emitting DECSCUSR re-enable cursor blink — "force static cursor" must override the `open cursorStyleChanged` callback to re-assert steady styles in Efficient tier.
8. **§1.2:** `EmbeddedTerminal.updateNSView` runs on every state publish; re-applying `nativeBackgroundColor` each time does redundant invalidation work. Fix: cache last applied color; assign only on change (verified: setter does not clear scrollback).

### Product & UX
9. **§2.7 (new):** ⌘F fallback has no spec section — with focus outside a terminal, focus the selected worktree's first pane (per §2.1), then invoke find.
10. **§4.3:** triage sort re-orders rows under the user mid-scan; ⌃1–9 targets become non-deterministic. Fix: hysteresis (status must persist across two consecutive polls before the sort key changes) and document; also `completed` should outrank `running` (finished work needs action): `failed > awaitingInput > completed > running > idle`.
11. **§4.2/§4.4:** row overload. Fix: diff badge only when dirty > 0, muted single accent, dirty dot in compact mode; PR badge only when state is non-green (green-quiet, red-loud); auto-enable compact above ~12 visible rows.
12. **§3.1/§3.3:** drop window-not-key as a materials/animation trigger (pops on every app switch — apply to animations at most); emoji → SF Symbols (`bolt.fill` / `leaf.fill`), trigger string lives in popover only, fixed-width pill; thermal hysteresis (≥15–30 s dwell, downgrade at `.serious`+); tier change crossfades ~0.15 s (the one animation permitted in Efficient).
13. **§5.3:** uncommitted-count line is dead data (hard block in `Git.swift:48` means dirty worktrees never reach the dialog); make "riskless → one line" explicit; adopt proposed copy (`⚠ N unpushed commits — branch is kept, but not backed up remotely.` / `⚠ 1 pane has a running program — its session will be terminated.`).
14. **§2.4:** ⌘W must be specified: closes focused pane; when last pane, closes tab (confirmation preserved). Prefer ⌃⌘C over ⇧⌘C for copy path (⇧⌘C = terminal paste-selection muscle memory).

### Safety & regression (adversarial)
15. **§1.1:** teardown ordering + failure atomicity. `endSession` throws — a failure after `Git.remove` succeeds would skip metadata cleanup → persisted tabs pointing at deleted dirs. Fix: end sessions for all panes under `tree.path` **first** (closeTab shape), then `Git.remove`, then unconditional metadata cleanup; surface partial failure per `ARCHITECTURE.md:89`. Document that `resetWorkspaceMetadata`'s detach-only is intentional (dirs still exist).
16. **§4.1:** exhaustive state inventory required: `"Starting"`, `"Shell"`, bare `"Exited"`, `"Ended"`, `"Exited N"`, `"Exited signal"` (nil exit code), `"Launch failed: …"`, `"Program active"`. `"Ended"` must be its own neutral case; `"Exited signal"` → failed. Status is **derived, never persisted** (no `workspace.v2` schema migration).
17. **§5.1:** destination path is computed inside `Git.create` — streaming tab must be created under the repo root key and moved on success; on failure/cancel: clean the exact owned checkout/registration through Git, preserving locks and unrelated registrations, keep any hook-created branch commits and report recovery details (corrected by the 2026-11-04 review).
18. **§3.1:** require dwell-based hysteresis (downgrade after trigger holds N s; upgrade after all triggers clear for M s).
19. **§5.3:** `git log @{u}..` fails without upstream/detached HEAD — probe with `rev-parse --abbrev-ref --symbolic-full-name @{u}` first (or `allowFailure` on `Git.run`); argv-only, no shell string composition.

## Key non-blocking guidance adopted
- `lastFocusedPaneID` transient (not in `SavedWorkspace`); NSOpenPanel dismissals included in snapshot/restore.
- Palette Escape hierarchy: exit substate → clear query → close.
- App-level `didBecomeActive/didResignActive` (not per-window) for tier triggers; publish `objectWillChange` explicitly on tier flips.
- Drop "ligature toggle" and "FPS cap" claims (no such API in pinned SwiftTerm `e213ebb`; smooth scroll is an internal stub).
- Popover metrics computed on open, not continuously published.
- Wake refresh via `.onReceive(publisher)` on ContentView; banner replaces (not stacks) on repeated poll failures.
- ⌘⌫ = Remove worktree…, ⇧⌘⌫ = Archive (Finder muscle memory); plain ⌘C must copy terminal selection when one exists.
- Tab cycling follows `saved.tabs[path]` order, updates `activeTabs` + `save()`.
- New removal-cleanup Check needs GUI gating (`GROVE_RUN_GUI_CHECKS` pattern) — not a headless unit check.
- §4.5: render `awaitingInput` as "unknown/—" in UI until the protocol lands.


## Corrective branch review — 2026-11-04

The earlier teardown-first and prune-before-directory-cleanup recommendations were unsafe/incomplete. They are superseded by [UIUX-BRANCH-REVIEW.md](UIUX-BRANCH-REVIEW.md): eligibility before teardown, final Git recheck, cached sessions retained on failure, and cleanup of the exact owned failed checkout through Git, respecting locks and unrelated registrations. Branches are retained intentionally because a checkout hook may create commits. Approval of a plan did not prove implementation correctness. The new regression checks exercise these paths against real temporary repositories and owned sessions.
