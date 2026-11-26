# Launch audit: Grove 0.3.0

Run: 2026-11-26 · `optimistic-app-launch`, check only.

| Check | Result | Evidence |
|---|---|---|
| First frame blocked on network | No | No network on launch. `Workspace.init` reads UserDefaults only (`Workspace.swift:58-89`). |
| First frame blocked on `git` | No | Repository listing runs in `.task` after first render, off the main thread (`Grove.swift:231-243`, `Workspace.swift:389`). |
| Auth / session restore | n/a | No accounts. Terminal panes reattach to tmux sessions per pane when shown. |
| Launch fan-out | Bounded | Diff stats poll runs sequentially, one Git process at a time (`Workspace.swift:262-275`). |

Verdict: **n/a, no change needed.** Grove's launch already renders saved state first and refreshes in the background. Cold-launch timing on real hardware was not measured.
