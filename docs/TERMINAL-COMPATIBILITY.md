# Terminal compatibility

## Gemini CLI warning — investigation, 2026-11-02

The installed Gemini CLI is `@google/gemini-cli` 0.66.0, linked from `/opt/homebrew/bin/gemini`. Its bundled core compatibility detector defines `isGnuScreen()` as the truthiness of `process.env["STY"]`, then emits the warning reported by the user. Locally inspected evidence: `/opt/homebrew/lib/node_modules/@google/gemini-cli/bundle/chunk-RZ3ZVTZB.js`, lines 279126–279128 and the following compatibility-warning builder. The package identifies its primary source as [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli); [core compatibility source](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/utils/compatibility.ts) is an unpinned upstream reference, not a claim that main matches the installed bundle.

Grove's persistent launch path in [Session.swift](../Sources/Grove/Session.swift) creates and attaches to GNU screen. The warning therefore identifies the actual wrapper. Hiding the warning or removing screen's identifying variable while still running through screen would not repair protocol compatibility. The existing Settings persistence toggle can already create direct PTY sessions when disabled; only newly launched sessions change mode. Live screen sessions keep their current wrapper.

No tmux binary was found in PATH, `/opt/homebrew/bin/tmux` or `/usr/local/bin/tmux` during this investigation. Choosing tmux persistence requires making that executable available and verifying input, detach/reattach, cleanup and packaged-app restoration. Choosing a direct PTY avoids screen entirely but those shell processes do not survive quitting the app.

## Implemented migration

The user selected tmux persistence. Homebrew tmux 3.8 was installed for local execution; it remains an external dependency rather than a copied binary in Grove. New persistent panes use Grove’s separate `-L grove` server and bundled tmux.conf. The launcher clears inherited multiplexer context before creating a new PTY, then the actual daemon provides its own context. Per-pane environment is passed explicitly to avoid reusing the first session’s worktree identifiers from the shared server.

Live screen sessions are reattached before considering a new tmux session. They are never killed or restarted automatically. Open a fresh terminal tab to use tmux and run Gemini there; finish/save old work before closing legacy tabs. Close/Stop/Restart and explicit end-sessions target the exact saved session ID on the Grove server and check legacy screen too.

The PTY fixture verifies that the new shell has no STY, has TERM=tmux-256color, passes Ctrl-B and preserves process identity after detach/reattach. This establishes that Gemini’s GNU screen detector is false in that shell. It does not establish complete rendering or keyboard compatibility for every Gemini release.
