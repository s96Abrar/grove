# Changelog

## Unreleased

- Release plan: `docs/RELEASE-PLAN.md` covers the first tagged release, its criteria and checklist, versioning and next candidates.
- Performance measurement: `scripts/perf.py` (`make perf`) reports launch-to-terminal time, idle memory and CPU, and bundle size; CI shows the numbers in each run summary. README gains status and project badges.
- UI states: "no worktrees match" message with Clear search; branch names and clone URLs are validated as you type; common network, SSH, credential, GitHub CLI and macOS privacy errors are explained in plain language with the raw output kept as details; copying a path or branch name confirms with a notice; empty folders in the file browser say so.
- Clone shows a progress banner with Cancel, removes a partial checkout when cancelled, and gives up on an HTTP transfer that stalls below 1 KB/s for a minute.
- Security CI: Dependabot weekly updates for Actions and Swift packages, plus OSV-Scanner advisory checks of `Package.resolved` and a gitleaks secret scan on pushes, pull requests and weekly.
- Repositories and folders can be removed from Grove individually (right-click → Remove from Grove…); files, branches and worktrees on disk are kept.
- Privacy: Reset Workspace Metadata now deletes the workspace and its backup instead of keeping a full copy, and can also delete the recovery copy of earlier unreadable metadata.
- CI: SwiftPM build products are cached between runs, and a hung run now times out after 25 minutes instead of 45.
- Security: `grove://` links (and the `grove` CLI) now ask before adding a new folder or creating a worktree, and the file browser asks before opening scripts, launchers, installers or executables.
- CI: quality checks run on the Apple Silicon runner only; tagged releases still build and verify the universal (arm64 + x86_64) app.
- Community files: contributing guide, Contributor Covenant 2.1 code of conduct, security policy with private vulnerability reporting, support page, bug/feature issue forms and a pull request template.
- Terminal font guard: SwiftUI update passes no longer re-assign the terminal font on every state publish, avoiding SwiftTerm FontSet rebuilds, cell-metric recomputes, selection clears and full re-renders for every open terminal.
- Multi-window Changes tracking: each window's Changes pane registers its own visibility, so closing the pane in one window no longer stops diff updates in another.
- Triage status publication: worktree triage icons and sorting refresh as soon as stable agent/busy statuses change, instead of relying on unrelated poll publishes.
- Restored terminal font guard: `updateNSView` assigns the terminal font only when it actually changed, and ended panes get their font applied at creation so the guard cannot skip them via a stale marker.
- Split-pane leaves are keyed by pane id: closing a pane or creating a split no longer reuses the previous pane's terminal NSView for a different session (stale PTY display).
- Changes-pane visibility gating: background poll ticks skip the full `git diff` fetch unless the Changes pane is on screen; opening the pane refreshes it immediately.
- Changes view memoization: the diff text is parsed once per change instead of on every view-body evaluation, and per-file addition/deletion counts are computed at parse time.
- Sidebar owns its search state: sidebar search keystrokes no longer re-evaluate the whole content view and every terminal pane's NSViewRepresentable update pass.
- Poll invalidation guards: worktree lists, status, diff and diff-stats are published only when their values actually change, so idle poll ticks no longer re-render every observing view.
- Terminal font glyph fallback: Nerd Font/Powerline prompt icons render from an installed patched font when the selected terminal font lacks them.

## 0.3.0 — release preparation

- Original Grove app icon with full macOS icon sizes and source artwork.
- Versioned, staged app packaging with build provenance, license notices and hardened runtime.
- Workspace-state validation, legacy migration, last-good backup recovery and preservation of unreadable data.
- Tab startup commands are transient; restoration never automatically repeats an old script.
- Confirmed tab closure ends sessions; regular app quit preserves persistent shells.
- Active-tab selection is saved; cold-start deeplinks wait for workspace loading.
- Worktree removal protects ignored files as well as tracked/untracked changes.
- Local delivery ZIPs with checksums and round-trip validation.
- Tag-only ad-hoc release pipeline, prepared native-architecture CI and local Git history.

Apple signing/notarization are intentionally excluded by user policy. Hosted CI and publication have not run; no remote exists. See docs/RELEASING.md for prerequisites and remaining validation.

## 0.2.0

Independent SwiftUI workspace, embedded SwiftTerm PTYs, screen-backed persistent sessions, worktrees, nested splits, scripts, palette, files, Git review and basic CLI/deeplinks. No telemetry or activation.
