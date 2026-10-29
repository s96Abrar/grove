# Supacode investigation

Inspected upstream commit `1ffcc2e93c3f74fe3d52183176542fa8852ad2ba` on 2026-10-28. Source checkout: `/tmp/supacode-reference`. This is source inspection, not observation of the installed app's runtime.

## How it works, with evidence

| Layer | Finding | Pinned source evidence |
|---|---|---|
| App composition | A reducer owns repository and terminal orchestration state. | [AppFeature.swift, lines 54–100](https://github.com/supabitapp/supacode/blob/1ffcc2e93c3f74fe3d52183176542fa8852ad2ba/supacode/Features/App/Reducer/AppFeature.swift#L54-L100) |
| Repository model | Repository location identifies local/remote repositories; each repository holds worktrees. | [Repository.swift](https://github.com/supabitapp/supacode/blob/1ffcc2e93c3f74fe3d52183176542fa8852ad2ba/supacode/Domain/Repository.swift#L5-L39) |
| Worktree model | Each task has a working directory, branch attachment state, location identity and script environment. | [Worktree.swift](https://github.com/supabitapp/supacode/blob/1ffcc2e93c3f74fe3d52183176542fa8852ad2ba/supacode/Domain/Worktree.swift) |
| Git integration | Local discovery calls a bundled wt script and decodes JSON. Standard Git porcelain parsing and worktree creation also exist for remote repositories. | [GitClient.swift, lines 100–245](https://github.com/supabitapp/supacode/blob/1ffcc2e93c3f74fe3d52183176542fa8852ad2ba/supacode/Clients/Git/GitClient.swift#L100-L245) |
| Rendering | GhosttyKit is a build dependency, alongside ComposableArchitecture, Dependencies and Sparkle. | [Project.swift](https://github.com/supabitapp/supacode/blob/1ffcc2e93c3f74fe3d52183176542fa8852ad2ba/Project.swift#L37-L52) |
| Persistence | Interactive terminal launch wraps the shell with `zmx attach <sessionID>`; scripts have a separate launch path. | [ZmxClient.swift, lines 406–435](https://github.com/supabitapp/supacode/blob/1ffcc2e93c3f74fe3d52183176542fa8852ad2ba/supacode/Clients/Zmx/ZmxClient.swift#L406-L435) |
| Agent presence | Hooks emit OSC 3008 through the terminal; the Unix socket handles CLI commands/queries rather than presence events. | [AgentHookSocketServer.swift, lines 8–17](https://github.com/supabitapp/supacode/blob/1ffcc2e93c3f74fe3d52183176542fa8852ad2ba/supacode/Infrastructure/AgentHookSocketServer.swift#L8-L17) |

The resulting workflow is: select repository → create isolated worktree → create terminal surfaces rooted there → launch coding agents → receive status through terminal hooks → review Git/PR state. Isolation comes from Git; terminal emulation comes from Ghostty; survival across app restarts comes from zmx.

## Original Grove baseline (historical; superseded by 0.2)

Grove is an independent SwiftUI implementation. No upstream implementation code or assets were copied. It uses system Git directly with separate arguments, creates new branches in sibling `.grove-worktrees` folders, lists existing worktrees, persists repository choices, provides concurrent command sessions, shows status and staged/unstaged tracked diffs, and opens Terminal.app for real interactive agents.

The embedded console is a noninteractive command runner, not a terminal emulator. Commands receive EOF on stdin. Console sessions and transcripts are memory-only and do not reattach after quit. Terminal.app shells are independent of Grove. Agent presence hooks, embedded TUI rendering, splits, SSH, GitHub PR integration and a CLI are not implemented. These remain substantial differences from Supacode.

Grove 0.2 supersedes these original terminal limitations with embedded SwiftTerm PTYs and screen-backed sessions. See [current user guide](USER-GUIDE.md) and [feature coverage](FEATURE-PARITY.md); the baseline above is retained as investigation history.

## Original REA setup check

REA 6.8.0 doctor found installed skill version 49 aligned, Node 26.12.1 healthy, Codex registration missing, and no available native analysis engines. The user approved the scoped MCP registration; backup is `~/.codex/config.toml.rea.backup`. REA tools require a client restart. No Hopper installation was authorized. This investigation uses source evidence, not REA-generated binary evidence.

Packaged-app REA inspection has since been performed using the CLI. See [REA findings](REA-FINDINGS.md) for retained Evidence IDs, artifact identities and precise limits.
