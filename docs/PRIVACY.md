# Privacy and external effects

Grove is an independent local macOS application. No Supacode implementation code, assets, telemetry SDK, analytics identity or update infrastructure is adopted. Its terminal renderer dependency is the MIT-licensed SwiftTerm, pinned in `Package.swift` to the exact release `1.99.2`. A compatible workflow does not imply Ghostty configuration compatibility.

## Telemetry policy

Grove does not intentionally collect usage analytics, send crash reports, upload repository contents, or contact a Grove/Supacode telemetry backend. Telemetry is excluded by design, not a disabled tracking feature waiting for opt-in. macOS may independently produce local diagnostic reports according to system settings; those are not Grove network telemetry.

This is a policy plus a bounded implementation observation: current `Sources/Grove` contains Git, tmux/legacy screen, shell and opt-in GitHub CLI process launches, UserDefaults storage, directory browsing and Launch Services actions, with no application-owned analytics SDK. New code and dependencies must be checked against this policy before release. This statement does not claim that every command, shell startup file, external coding agent or OS service is network-free.

## Local data

Current Grove stores workspace metadata in UserDefaults `workspace.v2`: repository/folder paths, selected worktree and active tab, tab/pane UUIDs, recursive split layout, pins, archives, worktrees muted for notifications and script names/commands/scopes. The previous valid workspace is retained as workspace.v2.backup; metadata that cannot be read is preserved as workspace.v2.unreadable. Recovery uses a validated backup or blocks normal metadata saves until an explicit reset. Settings → Reset Workspace Metadata deletes the workspace and its backup without keeping a copy; a recovery copy of earlier unreadable metadata stays unless you choose **Reset and Delete Recovery Copy**. `defaults delete local.grove.workspace` removes every Grove preference and copy. These copies can include script commands and are local, not uploaded. Preferences in the same UserDefaults domain store appearance, terminal font name and size, persistence, GitHub opt-in, worktree base ref, fetch-before-create, attention sorting, awaiting-input detection, waiting-for-input notifications (off by default), sidebar pull request status (off by default), compact sidebar, the preferred Open application and the visual performance profile. Real Git branches/worktree directories are created on disk. Persistent shells and their daemon-managed state remain local under Grove’s private tmux server or the legacy system screen mechanism. Grove no longer needs external Terminal `.command` launchers. Confirmed tab-close ends its owned persistent sessions before removing metadata. Ordinary app quit keeps persistent shells alive. Cleanup failures are reported and retain the affected tab metadata. Earlier versions may have left detached orphan sessions; no general automatic retention/deletion policy is implemented. With awaiting-input detection on, Grove reads the last lines of each live terminal screen in memory every few seconds to spot prompts; that text is not stored, logged or sent. Optional notifications go through macOS Notification Center on this Mac and contain only the branch and repository names. Terminal output can contain secrets printed by user commands. Treat local logs, transcripts, diagnostic bundles and backups as potentially sensitive.

No Grove account is required. Repository files remain at their local paths unless an explicitly run command, agent, remote action or future integration sends them elsewhere.

## External calls and who initiates them

| Action | Possible external destination | Scope |
|---|---|---|
| SwiftPM dependency resolution during development | GitHub and dependency-declared package sources | Downloads build dependencies; not runtime app telemetry. Inspect `Package.resolved` and dependency manifests. |
| Fetching reference source / REA package for this investigation | GitHub / npm registry | Development/investigation tooling, separate from Grove runtime. |
| Entering a shell command or running a saved script | Any destination that executable chooses | User executable code runs with the user’s permissions; Grove does not restrict its network effects. |
| Running Codex, Claude or another agent in the terminal | The agent’s configured service endpoints | Agent installation, authentication, data handling and network behavior belong to that agent. |
| Git fetch/push/clone or repository hooks | Configured Git remotes and hook-selected destinations | Clone is explicit. Optional fetch-before-create (off by default) runs git fetch --prune before creating a worktree; push and other terminal commands are user code. Local status/diff/worktree discovery needs no remote request. |
| Opt-in GitHub lookup | GitHub instance configured for local `gh` authentication | Executes `gh pr view` for the selected worktree on explicit palette action. With **Show pull request status in the sidebar** also on (off by default), runs `gh pr view <branch>` for each visible worktree about every five minutes while Grove is active; results stay in memory. No PR mutation controls. |
| Future SSH workspace | User-selected SSH host | Document connection reuse and remote command effects when implemented. Not present in the original baseline. |
| Clicking an external link/opening another app | Chosen URL/application and its own services | Launch Services hands off to the selected external application. |

No automatic updater is implemented. Any future updater must use explicitly documented Grove infrastructure and must not add telemetry as part of update checks.

## Credentials and controls

Grove should use the existing SSH/agent/forge clients’ credential mechanisms and must not copy tokens into workspace metadata or transcripts. Do not paste credentials into commands that save shell history. Review repository lifecycle scripts and shell startup files before running them; they can access the same files and network as ordinary Terminal commands.

For verification, inspect dependency manifests and notices, search source for network/analytics clients, and observe the packaged app with a declared network-capture scenario where available. A source search is a bounded observation and cannot prove that an external executable never contacts a service. Retained REA evidence must state exactly what was observed.

## Build and release services

Local Git tracking has no remote. Prepared workflows run on a future GitHub remote only after it is added; release jobs contact GitHub for artifact/release publication and perform no Apple signing/notarization calls. This is developer-initiated delivery infrastructure, not application telemetry. There are no scheduled release triggers. Apple signing/API credentials and keychain import are not part of the release pipeline. See [release policy](RELEASING.md).
