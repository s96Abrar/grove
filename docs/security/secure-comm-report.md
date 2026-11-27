# Secure communication report: Grove 0.3.0

Run: 2026-11-26 · `secure-app-server-comm`, light pass. Grove has **no first-party server**, so TLS configuration, pinning and the interception test (§2-3, §7) are n/a. Recorded in `docs/lifecycle/decisions.md`.

| § | Area | Result | Evidence |
|---|---|---|---|
| 1 | Endpoint inventory | Done | No `URLSession` or HTTP client in `Sources/`. Network only via user-initiated `git clone` (`Workspace.swift:479`), optional `git fetch --prune` (`Workspace.swift:441`, off by default) and opt-in `gh pr view` (`Workspace.swift:431`; since v0.4 also an opt-in sidebar poll about every five minutes per worktree, `pollPullRequests`). Destinations are the user's Git remotes and `gh` host. |
| 2-3 | TLS / identity / pinning | n/a | Delegated to Git, OpenSSH and `gh`. Clone refuses `http://`, `file://`, `ext::` and other transports (`Workspace.swift:475`). Grove's helper processes have no terminal, so OpenSSH cannot ask about an unknown host key and the clone fails closed (unless the user has configured `SSH_ASKPASS` or `StrictHostKeyChecking=no`). |
| 4 | Payloads | Pass | Only `gh` JSON fields `number,title,state,url,mergeable,statusCheckRollup` are requested. |
| 5 | Token storage | Pass | Grove never reads or stores Git/`gh` credentials. `GIT_TERMINAL_PROMPT=0` and `GH_PROMPT_DISABLED=1` stop credential prompts from hanging hidden processes (`Git.swift:21`, `Workspace.swift:547-548`). |
| 6 | Client-side leakage | Pass with note | PR output, status and diff stay in memory only (`Workspace.swift:10-12`). Terminal scrollback lives in the user's tmux server, not in Grove's metadata. Note: `fetch --prune` uses whatever remote URL the repository has configured, including plain `http://`; that is user configuration. |
| 7 | Interception test | n/a | No first-party host. |

No Blockers or Should-fix items from this skill.
