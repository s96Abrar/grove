# Ship check: Grove 0.3.0 (native macOS, no backend)

Run: 2026-11-26 · `vibe-app-security-check`, partial (only the checks that apply to a native app with no server). Static review of `Sources/`, `scripts/`, `Resources/`, `.github/` and Git history. No live requests.

| # | Check | Verdict | Evidence |
|---|---|---|---|
| 1 | Open database / RLS | n/a | No database or BaaS. Local state is UserDefaults (`WorkspaceState.swift:125-150`). |
| 2 | Public file storage | n/a | No cloud storage. |
| 3 | Login enforced only in the client | n/a | No accounts or server. |
| 4 | Secrets in front-end code / bundle | **PASS** | No key/token patterns in `Sources/`, `scripts/` or full Git history (AWS, GitHub PAT, OpenAI-style, Slack, Google API key, private-key headers). Bundle adds only `tmux.conf`, `AppIcon.png`, `scripts/grove` and `Notices/` (`scripts/package_app.py:44`). `.gitignore` excludes `.env*`, `*.p12`, `*.p8`, keychains. |
| 5 | Rate limits | n/a | No server endpoints. |
| 6 | Input validation | **FAIL (Should-fix)**, see S-1 to S-3 | Command construction itself is sound: Git runs argv-only with `-C` and `--` (`Git.swift:15-31, 65, 69`); branch names allow-listed (`Git.swift:72-76`); base ref rejects leading `-` (`Git.swift:77`); clone accepts only `https://`, `git@`, `ssh://` and passes the URL after `--` (`Workspace.swift:474-479`); tmux/screen wrapper single-quotes every value (`PersistentTerminal.swift:22-35`); `grove.json` import is size/type/count-limited and needs an explicit review sheet (`ScriptPreset.swift:27-55`). The failures are about *untrusted triggers*, not quoting. |
| 7 | Logging | **PASS** | No logging calls in `Sources/`. Errors are shown in the UI only and not persisted. |
| 8 | Backups | n/a (local app) | Workspace metadata keeps a last-good backup (`WorkspaceState.swift:141-146`). |
| 9 | Monitoring / spend caps | n/a | No paid services. |
| 10 | Dependencies | **UNVERIFIED** (Should-fix) | 4 SwiftPM packages pinned by revision in `Package.resolved` (SwiftTerm `e213ebb`, swift-argument-parser 1.8.2, swift-png 4.5.2, h 1.0.1). GitHub Actions pinned by SHA. No advisory database was queried and there is no Dependabot. |

## Findings

### S-1 · Fixed 2026-11-26 · `grove://` URLs act without confirmation

**Status:** `open` for a folder not already in the workspace, and `new-worktree`, now wait for a confirmation alert naming the folder or branch (`Workspace.handleURL` / `confirmURLAction`). Selecting a known worktree, `new-tab` and `split` stay unprompted. Covered by `testURLActionsWaitForConfirmation`.

`Workspace.swift:483-507` handles `grove://open?path=…`, `grove://new-worktree?branch=…`, `new-tab` and `split` directly. The scheme is registered for every user (`scripts/package_app.py:52`). Any web page, chat link or document can trigger it after the browser's own "Open Grove?" prompt, if the browser shows one.

- `open` adds an arbitrary directory as a repository, selects it, and runs `git status` / `git diff` in it (`Workspace.swift:108-121, 413-415`). That reads the directory's own `.git/config`, so a repository with `core.fsmonitor` set runs its command (see S-2).
- `new-worktree` runs `git worktree add` in the selected repository, which runs its `post-checkout` hook.

**Fix:** show a confirmation sheet naming the action and path for every URL-triggered action that changes state (`open`, `new-worktree`), or only accept them from the bundled `grove` CLI. Leave `select` and `new-tab` on paths already in the workspace unprompted.

### S-2 · Owner decision · Background Git commands honor repository-configured programs
The background polls (`Workspace.swift:265, 267, 413-415`, every 5 s or 15 s) run `git status` and `git diff` with the repository's own config. A repository with `core.fsmonitor`, `diff.external` or a textconv driver runs that program as you, with no action from you. `--no-ext-diff` covers only `diff.external` on the diff call (`Workspace.swift:415`). Every Git GUI has this property. VS Code answers it with a workspace-trust prompt.

**Options:** (a) pass `-c core.fsmonitor=false` (and `--no-ext-diff --no-textconv` on diffs) to the read-only poll commands. This only costs fsmonitor speed-ups. (b) Ask "Trust this repository?" when one is added. (c) Accept and document it in `docs/PRIVACY.md` and `SECURITY.md`. Worktree-creation hooks stay intentional (`Git.swift:102`).

### S-3 · Fixed 2026-11-26 · Single click in the file browser opens any file with Launch Services

**Status:** ordinary documents still open on one click; scripts, launchers, installers, bundles and executable files ask first, offering Open, Reveal in Finder or Cancel (`FileBrowser.mayRunCode`). Covered by `testFileBrowserFlagsCodeButNotDocuments`. Double-click-to-open was not adopted, to keep keyboard and VoiceOver activation unchanged.

`FileBrowser.swift:20` calls `NSWorkspace.shared.open(file)` on one click. In a cloned repository that includes `.command`, `.app`, `.terminal` and `.webloc` files. Git checkouts carry no quarantine attribute, so Gatekeeper does not prompt. One click on `run.command` runs it in Terminal.

**Fix:** open on double-click (as Finder does), and for executable types or bundles ask first or use "Reveal in Finder".

### S-4 · Fixed 2026-11-26 · Dependency advisories not checked

**Status:** `.github/dependabot.yml` opens weekly update PRs for GitHub Actions and Swift packages, and `.github/workflows/security.yml` runs OSV-Scanner over `Package.resolved` (fails on any known advisory) and a gitleaks secret scan on pushes, pull requests and weekly. SwiftTerm is pinned by revision, so Dependabot cannot bump it; move it to a version tag to get updates.

Add Dependabot for `github-actions` and `swift` (one `.github/dependabot.yml`). Re-check advisories when SwiftTerm's pin moves.

## Not covered
Runtime tampering, binary hardening beyond the existing hardened-runtime and ad-hoc signature checks (`scripts/verify_app.py:24`), and what commands you type in the terminal do (out of scope by design, see `SECURITY.md`).
