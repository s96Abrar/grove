# Validation — Grove 0.2

Checks executed on Apple Silicon with Swift 6.4 / Xcode 27.1. This records observations; the feature matrix includes remaining work.

- Debug compilation passed for the embedded SwiftTerm PTY, screen wrapper, persisted layout models, nested splits, file browser, settings, scripts, palette and CLI/deeplink routing.
- Final release packaging passed for Grove 0.2, including the worktree-management changes. `codesign --verify --deep --strict`, `plutil -lint` and arm64 Mach-O inspection passed.
- `Checks/GitCheck.swift` passed against real temporary repositories: discovery, paths with spaces, branch/worktree creation, file isolation, staged diff, invalid/duplicate branch rejection, branch rename, base ref selection, dirty/main worktree removal rejection and clean worktree removal.
- `Checks/screen_check.py` passed using real PTYs and the system screen backend: interactive command input, daemon survival after detach, and reattachment to the same shell PID. The test creates and tears down only its uniquely named screen session.
- CLI argument parsing/help passed for open, select, new-worktree, new-tab, split, list and sessions.
- A bounded source search found no app-owned URLSession, analytics SDK, telemetry client or activation client in `Sources`/`Package.swift`. The settings UI contains explanatory text matching those words. This is a source observation, not a full network capture of user-launched commands.
- REA inspected the installed Supacode bundle and executable metadata. [Evidence IDs, retained files and limits](REA-FINDINGS.md) are recorded separately.

## Packaged app terminal launch

The final `dist/Grove.app` was launched using `open -n --env GROVE_VERIFY_PATH=/tmp/grove-ui-check`. Its isolated workspace launched a real SwiftTerm PTY with the screen wrapper and executed a shell command that wrote exactly `interactive-terminal-ready` to the fixture marker. The app reported PID 51694 and main window 8963. [Runtime metadata](evidence/grove-runtime.json) and [marker](evidence/grove-terminal-marker.txt) are retained. No ordinary saved workspace metadata was written by this verification mode.

## Not established

Full Supacode feature parity, SSH hosts, coding-agent hook behavior, GitHub credentials/PR mutations, binary notarization and public distribution are not established by these checks. The packaged terminal launch was observed as described above. The full packaged application termination/relaunch check also passed, as recorded below; visual scrollback rendering remains unverified.

## REA UI observation limit

`observe_native_ui` targeted only Grove PID 51694 / window 8963. REA returned `capability_unavailable`, reason `screen-recording-denied`. No screenshot or AX result was obtained, and no broader capture was attempted. [Returned diagnostic](evidence/grove-ui-observation.json). Granting Screen Recording to the REA host is an optional manual prerequisite for visual evidence; it is not needed to run Grove.

## Final packaged app restoration

`python3 Checks/app_relaunch_check.py` passed after fixing the macOS screen-list exit-status edge case. It launched app PID 76345, verified shell PID 76355, terminated that app with SIGTERM, launched app PID 76441 against the same isolated saved workspace, and confirmed the same shell PID remained alive. Layout/tab/pane IDs stayed stable, the startup command did not rerun, and exactly one matching screen session existed. Both app instances and that test's screen session were cleaned up by the harness. [Retained result](evidence/grove-app-relaunch.json).

This proves restoration across app-process termination in this fixture. It does not assert normal menu-Q event delivery, visual scrollback rendering, or an authenticated coding-agent TUI. The final app bundle passed ad-hoc signature verification and Info.plist lint after packaging.
