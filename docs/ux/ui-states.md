# UI states audit: Grove 0.3.0 (macOS HIG)

Run: 2026-11-26 · `ui-states-audit`, static review of `Sources/Grove/*.swift` against the Apple Human Interface Guidelines (macOS). Not checked visually. Builds on the earlier UI/UX reviews (`docs/UIUX-*.md`).

## Scorecard

| # | State | Score | Evidence |
|---|---|---|---|
| 1 | Empty | Good | First-run main view with a primary action (`Grove.swift:205-212`); clean tree "Working tree is clean." / untracked hint (`DiffView.swift:228, 242`). Gaps: empty folder in the file browser shows a blank list (`FileBrowser.swift:17`). |
| 2 | Loading | Partial | Create sheet shows a spinner (`Grove.swift:262`). **Clone shows nothing**: the palette closes and the clone runs in the background with only disabled buttons as a hint (`Settings.swift:122-125`, `Workspace.swift:474-482`). (U-1) |
| 3 | Error | Partial | One generic alert, "Grove needs your attention", with raw Git output and only OK (`Grove.swift:267`). Background failures use a dismissible banner (`Grove.swift:221-222`). No recovery actions. (U-4) |
| 4 | Offline | Partial | Clone, fetch and `gh` failures appear as raw Git/`gh` text; no "check your connection" wording. Local work is unaffected (good). |
| 5 | Slow network | Partial (clone fixed) | Clone and fetch-before-create cannot be cancelled and have no timeout (`Workspace.swift:441, 479`; `Shell.run` waits indefinitely, `Workspace.swift:551`). (U-1) |
| 6 | No search results | Missing | Filtering the sidebar to zero matches leaves empty disclosure groups with no message (`Grove.swift:132`). (U-2) |
| 7 | Permission denied | Partial | macOS privacy denials (Desktop/Documents/removable volumes) surface as raw "Operation not permitted" text (`FileBrowser.swift:31`; Git errors). No pointer to System Settings → Privacy & Security. (U-4) |
| 8 | Session expired | Partial / mostly n/a | No Grove accounts. An expired `gh` login shows the raw `gh` error in the palette (`Settings.swift:127`) without suggesting `gh auth login`. |
| 9 | Form validation | Partial | Empty fields disable the primary button (`Grove.swift:264`, `Settings.swift:117`). An invalid branch name or clone URL is reported only after submit, in a modal alert, instead of inline (`Git.swift:72-74`, `Workspace.swift:475`). (U-3) |
| 10 | Success | Partial | Create and clone confirm by selecting the result. **Copy worktree path / Copy branch name give no feedback** (`Workspace.swift:181-189`). Restore notice is good (`Workspace.swift:217`). (U-5) |

## Findings

| ID | Severity | Finding | Fix |
|---|---|---|---|
| U-1 | Fixed 2026-11-26 (clone) | Clone has no progress, no cancel and no timeout; a slow or stalled remote leaves Grove silently busy | Show a progress row or sheet with Cancel (terminate the `Process`); same for fetch-before-create |
| U-2 | Fixed 2026-11-26 | No "No worktrees match '…'" message for an empty sidebar search | Add a message under the search field with a Clear button |
| U-3 | Fixed 2026-11-26 | Branch name and clone URL are validated only after submit, via alert | Validate as you type with inline helper text; reuse the `Git.create` allow-list |
| U-4 | Fixed 2026-11-26 (text guidance; no Retry/Open Settings buttons) | Errors are raw tool output with only OK; offline, permission and `gh` auth cases are not recognised | Map common cases (network unreachable, `Operation not permitted`, `gh auth`) to plain-language text with an action (Retry, Open Privacy Settings, show `gh auth login`); keep the raw text under "Details" |
| U-5 | Fixed 2026-11-26 | Copy path/branch have no confirmation | Reuse the transient notice banner ("Copied path") |
| U-6 | Fixed 2026-11-26 | Empty folder in the file browser shows a blank list | "This folder is empty" placeholder |

No Blockers. U-1 is the only Major finding.
