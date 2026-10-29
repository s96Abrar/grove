# Grove verification plan

[Validation](VALIDATION.md) records executed checks. This document defines repeatable checks and acceptance scenarios; unchecked scenarios are not proof of completion.

## Reproduce local checks

Run from the repository root on macOS with Xcode’s command-line tools:

```sh
swift build
swiftc Sources/Grove/Git.swift Checks/GitCheck.swift -o /tmp/grove-git-check
/tmp/grove-git-check
python3 Checks/screen_check.py
python3 scripts/grove --help
bash scripts/build-app.sh
codesign --verify --deep --strict dist/Grove.app
plutil -lint dist/Grove.app/Contents/Info.plist
file dist/Grove.app/Contents/MacOS/Grove
open dist/Grove.app
```

The Git check uses fresh temporary repositories and does not mutate the user’s working repositories. It covers worktree discovery, paths with spaces, branch creation, isolation, staged diffs, invalid/duplicate branch rejection, explicit base ref selection, branch rename, main/dirty removal rejection and clean worktree removal. Its printed fixture location can be inspected after the run. `Checks/screen_check.py` creates a dedicated PTY/screen fixture, sends interactive input, records the shell PID, detaches, reattaches and checks PID continuity. It cleans up its own screen session. This backend check passed; it is distinct from a complete packaged-app lifecycle test.

After launch, verify process liveness separately. An `open` exit code proves dispatch, not that the app remained alive. Record the actual packaged executable path and PID. Do not claim a visual/UI pass from a process check.

## Evidence to retain

For each release, record source revision or source-tree digest, toolchain/OS/architecture, package resolution, build command, executable path, build/signature verdict, test output, UI scenario outcome and remaining limitations. Retain screenshots only for observed screens. Retain REA’s complete Evidence JSON and its referenced artifacts rather than only a terminal preview.

## Behavior acceptance

| Area | Scenario | Required observation |
|---|---|---|
| Local Git | Create tasks in a repository with spaces and non-ASCII paths | Git lists the new worktree; branch and canonical path match UI identity; files remain isolated. |
| Worktree validation | Duplicate/invalid branch, unborn repository, missing checkout | Useful failure; no phantom sidebar item or claimed successful creation. |
| Lifecycle | Archive, restore, delete, delete with dirty files | Archive preserves files; unsafe deletion is rejected by shared operation; main checkout protected. |
| Refresh | Change branch and edit files externally while switching selection | Current row and diff converge; stale responses do not overwrite another worktree’s state. |
| Folder | Open a plain directory | Terminal and scripts work; Git-only actions are unavailable. |
| Interactive PTY | Enter shell input; use Ctrl-C; resize; run an installed full-screen TUI | Input, signal and geometry are correct; terminal text is not reduced to a noninteractive log. |
| Tabs and splits | Create nested splits, rename/move tabs, switch worktrees repeatedly | No duplicate shell launches; stable surfaces and focus; layout restores after relaunch. |
| Process persistence | Start a counter recording PID/timestamps; quit/relaunch | Same process continues, retained output reappears, no command replay. Metadata restoration alone fails this scenario. |
| Explicit termination | Quit with teardown | Only owned sessions terminate; later reattach reports absence honestly. |
| Scripts | Run repository/global and lifecycle scripts; exercise failure | Correct directory/context; correct trigger; exit status prevents inappropriate follow-up. |
| Settings | Change settings, restart; load older and malformed data | Choices survive; supported migrations work; original corrupt data is preserved for recovery. |
| CLI/deeplink | Valid/invalid IDs, unknown commands, no running app, timeout | Same validation as UI; clear errors; no arbitrary input under restrictive policy. |
| Agent hooks | Busy/idle/input events across two surfaces | Events route to correct identity; split/coalesced sequences parse; ordinary output remains intact. |
| Notifications | Muted/active/inactive surfaces, unread filters, retention | Delivery honors preferences and permission outcome; click focuses originating surface. |
| SSH | Owned test host, reuse connection, disconnect/reconnect | Authentication reuse, host-scoped paths and session continuity; no command replay. |
| Forge reads | Fixture PR/MR with pending/failing/passing checks | Real server state shown; absence, auth failure and unknown checks remain distinct. |
| Forge writes | Explicit disposable PR/MR fixture | Verify actual create/update/merge result; no production repository mutations during generic testing. |
| File explorer | Hidden, ignored, untracked, deleted and symlink paths | Defined enumeration policy, correct status and opening behavior. |
| Updates | Grove-owned signed test feed and test key | Signature rejection/acceptance, channel choice and relaunch verified against the packaged app. |
| Accessibility | Keyboard-only workflows, VoiceOver labels, resizing | Core tasks reachable without pointer; controls labeled; content usable at supported window sizes. |

## REA verification boundary

Use the installed Supacode bundle as the explicitly selected reference artifact. Resource metadata can be inspected without a native analysis engine; that does not establish function behavior. Record installed version/build, resource provenance and any reported hashes. Never equate a directory identity with executable SHA-256.

Native decompilation needs an available configured provider. A missing provider is an unresolved capability, not a reason to fabricate code evidence. Source inspection can explain available source; it must not be labeled REA runtime observation. If the MCP server is registered but tools are absent in the running client, use a supported CLI operation or reconnect; do not repeatedly rewrite registration.

## Release gate

A release may claim only the feature rows whose implementation and acceptance evidence are linked. Failed or unavailable SSH, forge, daemon or update scenarios remain explicit limitations. Passing compilation cannot close those rows.

## 0.3 release gate

Run make check: actual Git fixtures now include ignored-file protection; StateCheck.swift exercises valid/legacy state, dangling layouts, malformed metadata and backup recovery in an isolated preference suite. release_policy_check.py uses a real temporary Git repository to reject mismatched tags, dirty checkouts and missing signing/notary inputs. The GUI harness remains confined to a temporary workspace and verifies same-PID reattachment. scripts/verify_app.py checks version, icon/notices, architecture manifest, hardened signature and production identity requirements. release.py additionally round-trips the final ZIP. CI is prepared for native Apple Silicon and Intel runners; no hosted run has occurred.
