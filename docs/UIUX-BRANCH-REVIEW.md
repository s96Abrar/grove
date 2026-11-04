# UI/UX branch corrective review

Reviewed on 2026-11-04: `uiux-refactor`, base `main` at `5e88023`, commits `73977e3` (UI/UX refactor) and `c72a4eb` (unified/split diff viewer). The working tree was clean before this review. Source, architecture, development/release policy, UI/UX audit, implementation plan and council notes were read before fixes. The release policy remains ad-hoc-signed/non-notarized, tagged only, with local Git and no telemetry.

## Claims rechecked

| Earlier finding | Confirmed behavior and correction |
|---|---|
| Rejected removal stops sessions | Confirmed. Shared non-destructive Git preflight now precedes teardown; final Git validation remains after it. Main, locked, registered-worktree and dirty/ignored-file protections remain in the shared Git operation. |
| Failed removal can replay a script | Confirmed cache eviction. Cached ended/error sessions and metadata now survive failure; only successful removal evicts them. Tests request the same pane again and verify object identity remains stable. |
| Creation rollback leaves stale state | Confirmed registration bug. Cleanup unregisters/removes only the failed checkout through Git, preserving locked/refused checkouts with recovery guidance. **Correction to the earlier review:** branch retention itself is deliberately safe, since hooks may create commits. Branches are preserved and recovery text explains this. |
| Auto never schedules recovery | Confirmed. The SDK thermal notification constant replaces an incorrect raw name, verified with actual local notification delivery. Both transition deadlines are scheduled; interruptions/manual overrides cancel pending work. Tests use isolated preferences, injected time/power triggers and actual timer callbacks. |
| Palette captures unrelated arrows | Confirmed. Navigation now requires its query's actual key window, query focus and unmodified arrow keys. Other windows, modifiers and marked input-method composition pass through. Escape backs out of a subform, clears the query, then dismisses. |
| Triage setting/sampling ineffective | Confirmed. Pin priority remains first; optional attention sorting uses status committed only after two consecutive samples. General settings expose profile, sorting and compact controls. |
| Script UUID shown as shortcut | Confirmed. Stable action identity and optional shortcut label are separate fields; only real shortcut text is rendered. |
| Diff metadata filenames/quoted paths and right context lines | Newly confirmed in `c72a4eb`. Header fallback and C-escape/UTF-8 decoding preserve paths; unquoted header-delimiter tabs are removed. Split columns use their own line numbers. File-mode metadata and no-newline markers remain visible. |

## Before and after evidence

The initial native XCTest run exercised the actual executable module with temporary repositories and owned sessions: **6 cases, 10 assertion failures across 5 cases**. These reproduced rejected-removal termination/cache loss, post-teardown session recreation, stale failed-checkout registration, ineffective triage, and wrong diff paths/right context numbering. The positive exact-session-removal case passed before the fixes.

After corrections, the expanded suite passed **11 cases, zero failures**, including locked-worktree protection and exact rollback cleanup. It also checks a real Git fsmonitor barrier during removal: close/split/new-tab/select attempts cannot create a replacement pane while final Git validation is suspended. Hook-created commits remain reachable after failed creation. The thermal delivery check first failed against the incorrect raw notification name, then passed with the SDK constant. A separate profile check verifies the real scheduled callbacks in both directions without changing system power settings.

Independent before/after reviews identified and resolved two additional issues: replacement-tab creation during an in-flight removal, and Git's tab delimiter after unquoted space-containing content-header paths. Those scenarios were added to the final checks. A subsequent locked-hook fixture exposed a cleanup fallback bypassing Git locks, and a temporarily missing unrelated checkout exposed overly broad pruning. Cleanup now respects locks and targets only its own registered checkout; both scenarios are regression-covered. SwiftPM tests and the profile check are part of `scripts/check.sh`.

The final `GROVE_RUN_GUI_CHECKS=1 bash scripts/check.sh` completed successfully after all source corrections. It ran the profile and 11 XCTest cases alongside existing Git/state/script/open/release-policy/screen/tmux checks, rebuilt the host arm64 app, verified its bundle and ad-hoc signature, exercised installer rollback and passed packaged-app termination/relaunch. The relaunched app retained shell PID 10384, stable layout IDs and one matching tmux session, with no startup replay or GNU screen context. Workflow lint and whitespace checks also passed. Independent standards/safety and specification reviews found no remaining material issue in the changed fixes.

## Documentation corrections

`UIUX-PLAN.md` and `UIUX-PLAN-REVIEWS.md` previously recommended unsafe teardown-first/prune-before-cleanup ordering. The plan now specifies preflight → teardown → final Git check → success-only metadata/cache cleanup. The audit is labeled a historical snapshot; unsupported split-focus and shortcut-identity assertions are corrected. Architecture, development, testing, user instructions and feature coverage describe current behavior and distinguish proposals from delivered validation.

The restored-pane notice describes pane IDs loaded from saved metadata; it does not prove an existing daemon was reattached. Binary/mode/empty-file handling and combined staged/unstaged diff behavior are documented. Efficient mode shows a dirty marker when line counts have not been collected, instead of implying zero changed lines.

## Remaining acceptance boundaries

Model/parser/backend checks do not establish visual rendering or every keyboard interaction. Manual smoke remains for palette focus across windows and IMEs, actual menu shortcuts, live light/dark rendering, and profile/accessibility transitions. Agent awaiting-input detection, setup hooks, streaming/cancellable worktree creation, complete PR check-state badges, Efficient cursor suppression and performance sampling remain documented follow-ups. No hosted CI run, remote or published release is claimed.
