# Grove

An independent native macOS coding workspace with embedded interactive terminals, Git worktrees, tabs and nested splits. Grove’s own code is MIT-licensed; no Supacode code or assets are copied. It has no analytics, telemetry, account requirement or license activation. Its terminal renderer is MIT-licensed [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), pinned in `Package.swift`.

Requirements: macOS 14+, Swift tools 6.2+, system Git and `/usr/bin/screen`. Python 3 is needed for the optional CLI and backend check. Coding agents are installed/authenticated separately.

```sh
bash scripts/build-app.sh
open dist/Grove.app
```

Add a repository or plain folder with Command-O. Create isolated Git worktrees with Command-N; choose a base ref and optional pre-creation fetch in Settings. Rename branches or remove clean worktrees from their context menu; removal keeps the branch and rejects dirty/main checkouts. Run shells, builds and coding agents directly in Grove’s PTY terminals; an external terminal is no longer required. Create terminal tabs with Shift-Command-T and split them left/right or top/bottom from the split menu.

Grove 0.2 includes persisted workspace/tab/pane identities, selected worktree, pin/archive state, custom scripts, a fuzzy command palette (Shift-Command-P), clone, appearance/font settings, terminal search, a basic file browser, Git change review, an opt-in manual GitHub PR query using local `gh` authentication, and basic CLI/deeplinks. Screen-backed terminal sessions are enabled by default and can reattach to the same shell. Closing a persistent tab detaches its session; it does not terminate it.

This is not full Supacode parity. Active-tab/split-size restoration, agent-presence hooks, notification inbox, remote SSH workspaces, full forge actions, Git-decorated file exploration, automatic updates, and complete CLI control are still missing. See the [feature matrix](docs/FEATURE-PARITY.md) for precise coverage and verification limits.

Checks:

```sh
swiftc Sources/Grove/Git.swift Checks/GitCheck.swift -o /tmp/grove-git-check
/tmp/grove-git-check
python3 Checks/screen_check.py
python3 scripts/grove --help
```

The Git fixture check (including base-ref selection, branch rename and guarded removal) and PTY/screen backend check have passed. The latter proves interactive input and shell PID continuity across detach/reattach; it does not establish every packaged-app UI or full quit/relaunch scenario. The bundle is locally ad-hoc signed, not notarized for public distribution.

[Documentation](docs/README.md) · [User guide](docs/USER-GUIDE.md) · [REA findings](docs/REA-FINDINGS.md) · [Privacy](docs/PRIVACY.md) · [Validation](docs/VALIDATION.md) · [License](LICENSE)
