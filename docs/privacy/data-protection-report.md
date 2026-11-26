# Launch data protection report: Grove 0.3.0

Run: 2026-11-26 · `launch-data-protection-audit`. Grove is local-only, so there are no vendors, processors or cross-border transfers to assess (§2). The report focuses on the local data inventory (§1), `docs/PRIVACY.md` against the code (§3) and deletion/export (§4). Not legal advice.

## §1 Data inventory

| Store | Contents | Where | Cleared by |
|---|---|---|---|
| `workspace.v2` | Repository/folder paths, selected worktree, tabs, panes, split layout, pins, archives, collapsed roots, script names, commands and scopes, per-pane `GROVE_*` environment (paths, branch) | UserDefaults (`WorkspaceState.swift:72-80`, `:4-17`) | Settings → Reset Workspace Metadata (moved to `.unreadable`, see P-1) |
| `workspace.v2.backup` | Previous valid copy of the above | UserDefaults (`WorkspaceState.swift:125, 144`) | Reset (`:150`) |
| `workspace.v2.unreadable` | Corrupt data only (reset no longer copies the workspace here) | UserDefaults (`WorkspaceState.swift`) | Reset and Delete Recovery Copy |
| Preferences | `appearance`, `baseRef`, `compactSidebar`, `fetchBeforeCreate`, `fontName`, `fontSize`, `githubEnabled`, `openApplication`, `persistentTerminals`, `triageSort`, `performanceProfile` | UserDefaults (AppStorage; `PerformanceProfile.swift:26`) | Not cleared by reset |
| tmux / legacy screen sessions | Live shells and scrollback (may contain secrets you printed) | `tmux -L grove` server memory | Closing the tab, Quit and End Grove Sessions; reset only detaches (`Workspace.swift:508-512`) |
| Git checkouts | Your repositories and `.grove-worktrees/` | Disk | Remove worktree (branch kept) |
| In-memory only | `git status`/`diff` output, `gh pr view` JSON, errors | Process memory (`Workspace.swift:10-12`) | App quit |

No analytics, crash reporter, account or network-stored data. UserDefaults is included in Time Machine and migration backups, so all of the above except live sessions travels with your backups.

## §3 Privacy policy against the code

| Claim in `docs/PRIVACY.md` | Code | Result |
|---|---|---|
| No telemetry, analytics or crash upload | No HTTP client or SDK in `Sources/`; network only via `git`/`gh` | Match |
| GitHub lookup is manual and opt-in | `githubEnabled` default `false` (`Workspace.swift:38`); only on palette action (`Workspace.swift:428-434`) | Match |
| Fetch-before-create off by default | `Workspace.swift:33` | Match |
| AppStorage list ("appearance, font size, persistence, GitHub opt-in, worktree base ref and fetch-before-create") | Also stores `fontName`, `triageSort`, `compactSidebar`, `openApplication`, `performanceProfile` | **Drift** (P-2) |
| "unreadable/reset metadata is preserved as workspace.v2.unreadable" | `WorkspaceState.swift:148` | Match, but see P-1 |

## §4 Deletion and export

- **Export:** `grove list` prints the saved workspace as JSON (`scripts/grove:22-28`). Adequate.
- **Delete one repository from the sidebar:** "Remove from Grove…" on the repository's context menu (fixed 2026-11-26, P-3).
- **Delete everything:** Reset clears `workspace.v2` and its backup but **copies the current workspace into `workspace.v2.unreadable` first** (`WorkspaceState.swift:147-150`), where it stays indefinitely. The confirmation text says "Reset saved repositories, scripts and terminal layouts?" (`Settings.swift:41`), so someone resetting to remove script commands or paths keeps them on disk. (P-1)

## Findings

| ID | Severity | Finding | Fix |
|---|---|---|---|
| P-1 | Fixed 2026-11-26 | Reset keeps a full copy of the workspace (including script commands) in `workspace.v2.unreadable`, with no way to purge it in the app | Keep recovery copies only for corrupt data; for a user-chosen reset, delete all three keys, or offer "Also delete recovery copies". Document `defaults delete local.grove.workspace` as the full wipe |
| P-2 | Should-fix (low) | `PRIVACY.md` AppStorage list misses 5 stored preferences | Update the list |
| P-3 | Fixed 2026-11-26 | No way to remove a single repository or folder from the workspace | Add "Remove from Grove…" to the repository context menu: removes the root, its tabs and saved state, and ends or detaches its sessions; never touches files |
| P-4 | Owner decision | Workspace metadata (paths, script commands) is included in system backups | Accept (typical for preferences) or move scripts to Application Support with `isExcludedFromBackup` |

Evidence pack, vendor DPAs and incident plan: n/a for a local-only app with no processors.
