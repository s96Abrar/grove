# Grove user guide

Grove 0.3 is an independent native macOS app. It provides interactive shells inside the window, rather than the original noninteractive command console. Full Supacode parity is still tracked in [feature coverage](FEATURE-PARITY.md).

## Add a workspace

Open `dist/Grove.app`, then press Command-O or choose **Add Repository** to pick a local repository or plain folder. Git repositories show existing worktrees; a plain folder shows one folder workspace. Choose a sidebar row to select its working directory. Saved roots and the selected worktree survive relaunch. Use the disclosure arrow beside each repository or folder heading to expand or collapse its worktrees. Each heading remembers its state across launches; new repositories start expanded. Collapsing a heading keeps the selected worktree and its terminal sessions open. Searching temporarily expands the headings to reveal matching worktrees; you can collapse them during that search, and clearing the search restores your saved expansion states.

Press Shift-Command-P for the command palette. It matches characters in order, so abbreviated queries can find commands. Return executes the first matching action. The palette offers workspace navigation, add, clone, create worktree, new tab, refresh, scripts and manual GitHub lookup. Full arrow-key command selection is not implemented.

To clone, choose **Clone repository…** in the palette, enter an HTTPS or SSH Git URL, and select a parent folder. Grove creates a generated clone directory beneath it. Git credentials and host verification come from your existing tools.

## Create and organize tasks

Select a Git worktree, then press Command-N or select **New worktree**. Enter a new branch such as `feature/my-task`. Grove resolves the configured base reference to a commit (HEAD by default) and creates a checkout in a sibling `.grove-worktrees/<repository>/` directory. Existing files stay in their checkout. A plain folder cannot create Git worktrees. In Settings, change **New worktree base ref** to a branch, tag or commit. **Fetch before creating worktrees** optionally runs `git fetch --prune` first; it is off by default and uses your configured remotes/credentials. A failed fetch or unresolved base prevents creation.

Control-1 through Control-9 jump to visible indexed worktrees. Right-click a sidebar row to pin/unpin or archive/unarchive it. Pinned rows sort first. Archived rows are hidden until **Show archived** is enabled. Archive changes workspace visibility; it does not delete files or Git refs. The context menu also offers **Rename branch…** and **Remove worktree…**. Removal requires confirmation, rejects the main checkout and worktrees with tracked or untracked uncommitted files, and keeps the Git branch. It removes the checkout and its saved tab/pin/archive metadata. Persistent sessions detach rather than being automatically terminated, so inspect those deliberately if cleaning up. Branch-deletion, lifecycle hooks and automatic expiration remain unimplemented.

## Work in embedded terminals

Each tab contains one or more SwiftTerm-backed PTY panes. Type shell commands or start an installed coding agent such as `codex` or `claude` directly inside Grove. Commands have interactive stdin, terminal control sequences and resize support. They run with your user permissions; Grove does not install agents or authenticate them for you.

Press Shift-Command-T, use **New tab**, or select the plus button to add a terminal. Use the split menu for left/right or top/bottom panes. Splits form a persisted recursive layout; the focused pane is split when identifiable, otherwise the last pane is used. Right-click a tab to rename it or move it left/right within its worktree. Use Command-F to request the native terminal find UI; keyboard focus must be in the terminal. The pane’s **⌃C** button sends an interrupt through its terminal input. Each split pane also has an **×** button in its header. Confirm **Close Split** to end only that pane’s session and running commands; its sibling expands to fill the space, and the remaining layout is saved. Cancel keeps everything running. The last pane stays open; use the tab’s **×** to close the whole tab.

Workspace metadata saves tab/pane IDs and recursive split orientation/layout. The active tab/pane and divider geometry are not restored. Terminal font size is configurable in Settings. App appearance supports dark/light/system choices, while full terminal theme synchronization and custom per-pane colors remain incomplete.

## Persistence and session cleanup

Settings enables **Keep terminal sessions alive with screen** by default. A persistent pane creates a detached `screen` session named `grove-<pane UUID>` if none exists, then attaches to it. When that pane is recreated, it can attach to the existing shell rather than replay a command. Existing panes retain their launch mode when the setting changes.

Closing a tab prompts first and ends its sessions. If cleanup fails, Grove reports the error and keeps the tab metadata. Ordinary Quit preserves persistent shells. **Workspace → Quit and End Grove Sessions…** confirms and ends saved sessions, reporting failures. Earlier versions may have left detached orphan sessions; inspect exact IDs using the CLI or screen before ending any manually:

```sh
/usr/bin/screen -S grove-EXACT-PANE-UUID -X quit
```

The backend integration check proves interactive shell input and preservation of shell PID across detach/reattach. Full Grove quit/relaunch, scrollback restoration and every agent TUI remain app-level acceptance scenarios, not blanket guarantees.

## Shortcut help

Open **Grove → Settings…** (Command-comma), then **Help**, for the keyboard shortcut reference and terminal/script context notes. The sidebar tagline and terminal status/shortcut footer strips have been removed; terminal panes use the available space.

## Scripts and settings

Open macOS **Settings** for appearance, font, terminal persistence, worktree base/fetch preferences and GitHub opt-in. In **Scripts**, select **Add preset** for Run, Test, Deploy, Lint, Format or Custom. These categories start with an empty command, as they do in Supacode. Enter your project's actual command and save. The menu also includes clearly labeled Swift/npm/Grove examples; they require the corresponding tools and project targets and install nothing.

Scripts have a type, editable name, multiline command, icon, color and global or repository/folder scope. Click a saved row to edit it, use the up arrow to reorder it, or remove it with confirmation. Repository scripts appear before global scripts; the first available Run-type script is primary. **Command-R** selects/starts the primary script; **Command-period** stops that primary script's tab. All script types appear in the terminal **Scripts** menu and command palette.

For this project, select Grove's repository and choose **Import grove.json…** in Settings → Scripts. Review the commands, then confirm. The checked-in file provides **Build Grove** (`make build`, the primary Run script), **Check Grove** (`make check`), **Lint workflows** (`make lint`) and **Generate app icon** (`make icon`). Import replaces only that repository's saved scripts, preserving other repositories and globals. Reimporting does not append duplicates. Opening a repository never imports or executes its file automatically. The file is read from the registered repository root, not a selected linked worktree. See [grove.json](../grove.json) for the version-1 format: each script requires a UUID `id`, `name` and `command`; `kind`, `icon` and `tint` are optional. File-supplied `root` values are ignored and scope is assigned to the selected repository. Unsupported versions, duplicate IDs, malformed JSON, symlinks/special files and files over 1 MB are rejected.

Running a script opens one interactive terminal tab per script/worktree pair; choosing it again selects that tab. Output includes `[Grove script exited: N]` before returning to a login shell, including when the command uses `exit`. **Stop** ends that tab's screen session/foreground PTY group, including its splits. **Restart** stops the old tab and starts the current saved command in a fresh tab. These actions affect the whole script tab, including commands you started there afterward. Interrupt with the pane's **⌃C** button when you want to keep the terminal. Commands which deliberately daemonize or ignore termination may need their own shutdown command.

Commands start in the selected worktree and inherit the login-shell environment, plus `GROVE_WORKTREE_PATH`, `GROVE_ROOT_PATH`, `GROVE_BRANCH`, `GROVE_PANE_ID`, `GROVE_TAB_ID` and `GROVE_SCRIPT_ID` on script launch. Definitions, ordering and tab/script identities persist locally. Startup commands and their launch environment are excluded from saved pane metadata: reopening reattaches a surviving session, or starts a shell without replaying the command if the daemon is gone. Use **Restart** to explicitly run it again. Existing scripts migrate with their names, commands and scopes intact.

Scripts have ordinary shell access to your files and services; review commands before running them. Grove's scripts remain persistent terminal tabs with a printed exit code, unlike Supacode's temporary locked transcripts and structured running/completed status. Automatic setup/archive/delete/open-file hooks, script deeplinks and configurable script shortcuts are not implemented. See the [pinned Supacode source evidence](SUPACODE-SCRIPTS.md).

## Open the worktree in another app

The **Open** control sits beside **Scripts** in the terminal tab bar. Click its arrow to choose **VS Code**, **Xcode**, **Terminal** or **Finder**. Clicking the main Open button repeats the last selected app; this preference survives relaunch. Unavailable apps appear disabled, and availability refreshes when Grove becomes active. VS Code's `code` shell command is not required.

VS Code receives the selected worktree folder. Terminal opens a separate system Terminal window/tab rooted there. Finder reveals that worktree. Xcode prefers a `.xcworkspace`, then an `.xcodeproj`, then the root `Package.swift`, otherwise the folder. Project discovery stays within three levels of the selected worktree, ignores hidden/generated/dependency directories and symlinks, and chooses deterministically when several projects match. The worktree is passed as a file URL, so spaces, quotes and shell characters in its path are preserved. Launch errors appear in Grove. This Open menu uses built-in app actions; custom open-file shell hooks remain a separate future feature.

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

## Workspace recovery and 0.3 lifecycle changes

The active tab is now remembered. Workspace saves retain the previous valid snapshot; malformed metadata is preserved and a valid backup is restored when possible. If neither snapshot can be read, saves are blocked instead of replacing your data. Settings → Reset Workspace Metadata is an explicit confirmed recovery action; it does not delete source folders or Git worktrees. The unreadable/reset snapshot is retained locally.

Confirmed tab closure now ends that tab’s sessions and running commands. Regular Quit keeps persistent sessions alive; Quit and End Grove Sessions stops saved sessions and reports failures. Worktree removal also refuses ignored files such as .env. App packaging and tagged release instructions are in [Releasing](RELEASING.md).

Startup commands for a script tab run once when you choose the script. They are not persisted as automatic restore commands. A surviving screen session keeps its original process; if that session is gone, restoration opens a shell instead of silently repeating a build/deployment command. Saved script definitions remain in the Scripts menu for explicit reruns.
