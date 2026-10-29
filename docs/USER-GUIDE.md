# Grove user guide

Grove 0.2 is an independent native macOS app. It provides interactive shells inside the window, rather than the original noninteractive command console. Full Supacode parity is still tracked in [feature coverage](FEATURE-PARITY.md).

## Add a workspace

Open `dist/Grove.app`, then press Command-O or choose **Add Repository** to pick a local repository or plain folder. Git repositories show existing worktrees; a plain folder shows one folder workspace. Choose a sidebar row to select its working directory. Saved roots and the selected worktree survive relaunch.

Press Shift-Command-P for the command palette. It matches characters in order, so abbreviated queries can find commands. Return executes the first matching action. The palette offers workspace navigation, add, clone, create worktree, new tab, refresh, scripts and manual GitHub lookup. Full arrow-key command selection is not implemented.

To clone, choose **Clone repository…** in the palette, enter an HTTPS or SSH Git URL, and select a parent folder. Grove creates a generated clone directory beneath it. Git credentials and host verification come from your existing tools.

## Create and organize tasks

Select a Git worktree, then press Command-N or select **New worktree**. Enter a new branch such as `feature/my-task`. Grove resolves the configured base reference to a commit (HEAD by default) and creates a checkout in a sibling `.grove-worktrees/<repository>/` directory. Existing files stay in their checkout. A plain folder cannot create Git worktrees. In Settings, change **New worktree base ref** to a branch, tag or commit. **Fetch before creating worktrees** optionally runs `git fetch --prune` first; it is off by default and uses your configured remotes/credentials. A failed fetch or unresolved base prevents creation.

Control-1 through Control-9 jump to visible indexed worktrees. Right-click a sidebar row to pin/unpin or archive/unarchive it. Pinned rows sort first. Archived rows are hidden until **Show archived** is enabled. Archive changes workspace visibility; it does not delete files or Git refs. The context menu also offers **Rename branch…** and **Remove worktree…**. Removal requires confirmation, rejects the main checkout and worktrees with tracked or untracked uncommitted files, and keeps the Git branch. It removes the checkout and its saved tab/pin/archive metadata. Persistent sessions detach rather than being automatically terminated, so inspect those deliberately if cleaning up. Branch-deletion, lifecycle hooks and automatic expiration remain unimplemented.

## Work in embedded terminals

Each tab contains one or more SwiftTerm-backed PTY panes. Type shell commands or start an installed coding agent such as `codex` or `claude` directly inside Grove. Commands have interactive stdin, terminal control sequences and resize support. They run with your user permissions; Grove does not install agents or authenticate them for you.

Press Shift-Command-T, use **New tab**, or select the plus button to add a terminal. Use the split menu for left/right or top/bottom panes. Splits form a persisted recursive layout; the focused pane is split when identifiable, otherwise the last pane is used. Right-click a tab to rename it or move it left/right within its worktree. Use Command-F to request the native terminal find UI; keyboard focus must be in the terminal. The pane’s **⌃C** button sends an interrupt through its terminal input.

Workspace metadata saves tab/pane IDs and recursive split orientation/layout. The active tab/pane and divider geometry are not restored. Terminal font size is configurable in Settings. App appearance supports dark/light/system choices, while full terminal theme synchronization and custom per-pane colors remain incomplete.

## Persistence and session cleanup

Settings enables **Keep terminal sessions alive with screen** by default. A persistent pane creates a detached `screen` session named `grove-<pane UUID>` if none exists, then attaches to it. When that pane is recreated, it can attach to the existing shell rather than replay a command. Existing panes retain their launch mode when the setting changes.

Closing a tab prompts first. Persistent panes detach and their screen sessions stay alive; nonpersistent panes terminate. Closing a persistent tab also removes its saved pane IDs, so that detached session is no longer offered as a saved tab. The **Workspace → Quit and End Grove Sessions…** action asks for confirmation and requests termination of screen sessions referenced by saved pane IDs, then quits. Its current implementation does not surface individual cleanup failures and does not include orphaned sessions whose tab was already removed. Inspect sessions using the CLI or `/usr/bin/screen -list`; terminate only a session you identify deliberately:

```sh
/usr/bin/screen -S grove-EXACT-PANE-UUID -X quit
```

The backend integration check proves interactive shell input and preservation of shell PID across detach/reattach. Full Grove quit/relaunch, scrollback restoration and every agent TUI remain app-level acceptance scenarios, not blanket guarantees.

## Scripts and settings

Open macOS **Settings** for appearance, font, terminal persistence, worktree base/fetch preferences and GitHub opt-in. The Scripts tab stores a name, command and optional selected-repository scope. Run a script through the tab’s **Scripts** menu or the palette. It launches in a new interactive terminal tab, then leaves a login shell. Commands run only when selected; setup/archive/delete lifecycle hooks are not implemented.

Script definitions persist locally. Scripts can access the same files and services as ordinary shell commands. Review commands before running them. Script icons/tints, dedicated stop/restart controls and complete contextual IDs are still missing.

## Review Git changes and PR metadata

Select **Changes** to see short Git status and a combined tracked diff against HEAD, including staged and unstaged tracked changes. Untracked files appear in status only. Use **Files** to browse nonhidden directory entries, navigate into folders and open files in their system-default application. Git decorations, ignored-file policies and custom open-file scripts are not implemented. Local roster and selected-worktree status refresh every five seconds; **Refresh** explicitly requests new state. Finder reveals the selected directory.

For GitHub, first install/authenticate `gh` yourself, enable the GitHub setting, then choose **Refresh GitHub pull request** in the palette. The result is raw PR JSON for the selected worktree, including state, mergeability and check rollup. Reopen the palette to inspect the returned result if it closed while the request ran. This is manual metadata lookup, not live sidebar tracking, GitLab support, or PR mutation/merge controls.

## CLI and deeplinks

Use the local Python CLI; the packaged bundle also includes a copy under `Contents/Resources/grove`:

```sh
python3 scripts/grove open /absolute/path/to/repository
python3 scripts/grove new-worktree feature/my-task
python3 scripts/grove new-tab
python3 scripts/grove split vertical
python3 scripts/grove list
python3 scripts/grove sessions
```

Supported actions are `open`, `select`, `new-worktree`, `new-tab`, `split`, `list` and `sessions`. Mutation commands use the `grove://` URL scheme. When invoked inside a Grove pane, the CLI supplies `GROVE_WORKTREE_PATH` context; otherwise actions use the app selection. Split actions currently target the selected worktree’s last saved tab, not necessarily the visually active tab. `list` reads saved workspace metadata, not authoritative live state. `sessions` delegates to screen’s complete session list, which may include non-Grove sessions. App IPC queries, complete pane/tab commands and full repo/tab/surface contextual defaults are not implemented. Deeplinks do not accept arbitrary shell commands.

See [privacy](PRIVACY.md), [development](DEVELOPMENT.md) and [testing](TESTING.md) for storage, external effects and verification boundaries.
