# Validation — Grove 0.3.0

Local host: Apple Silicon, macOS 27, Swift 6.4 / Xcode 27.1. This records bounded observations, not a claim that every supported system or Supacode feature has been verified.

## Executed local checks

- Original vector app icon rendered to a committed 1024px PNG and visually inspected. Packaging generates all standard icon sizes and embeds AppIcon.icns with the correct Info.plist reference.
- Both arm64 and x86_64 release slices compiled, were merged into a universal Mach-O, and passed lipo/manifest verification.
- The universal local delivery ZIP was extracted into a fresh directory and passed bundle/version/icon/notices, hardened-runtime signature and architecture checks again.
- Git fixtures passed discovery, paths with spaces, isolated branch/worktree creation, staged diff, base-ref selection, branch rename, invalid/duplicate branch rejection, main/dirty/ignored-file removal rejection and clean removal. Ignored .env data was retained.
- Workspace-state fixtures passed JSON round-trip, legacy schema migration, active-tab metadata restoration, invalid pane/layout/schema rejection, last-good backup recovery, unreadable-data preservation and exclusion of one-time startup commands from restored panes.
- Real PTY/screen checks passed interactive input and shell PID continuity across detach/reattach.
- The packaged application harness passed termination/relaunch with stable layout IDs, the same live shell PID, no rerun startup command and exactly one matching screen session. It cleans up its own app processes/screen session.
- Release-policy fixtures cover matching immutable tags, invalid/mismatched tag and dirty-source rejection, and successful tagged preflight without Apple credentials. Earlier rejection tests for missing signing credentials are superseded by the accepted ad-hoc policy.
- Actionlint 1.7.12 passed the prepared workflows. Its downloaded macOS binary was verified against the pinned upstream release SHA-256. YAML parsing, immutable action-pin checks, shell syntax and documentation-link checks also passed. No release schedule trigger is present.

Commands: `make check`, `make lint`, and `GROVE_ARCHS="arm64 x86_64" python3 scripts/release.py --mode local`. The consolidated checks can reuse an already built universal bundle with `GROVE_SKIP_BUILD=1 GROVE_RUN_GUI_CHECKS=1 bash scripts/check.sh`.

## Real build failures corrected

The default Swift 6.4 swiftbuild engine compiled a dependency build-time helper for the destination Intel CPU, which could not run on the host without Rosetta. Explicit minimum-OS triples and SwiftPM's native engine keep build helpers host-native. Per-architecture scratch paths prevent cross-architecture cache collisions, and compiler parallelism defaults to two jobs after a resource-exhaustion error. No Rosetta install or sandbox disable was used. A source edit invalidated one in-flight build; all final application source was built together afterward. See RELEASING.md for the native-engine deprecation/toolchain upgrade caveat.

## Release limits

- Apple signing, notarization, stapling and Apple trust assessment are intentionally excluded by explicit user policy. Their absence is not an unresolved issue or release blocker. Current and future artifacts are described truthfully as ad-hoc-signed and non-notarized; integrity checks remain required.
- No Git remote exists. Hosted CI, protected tag/environment settings and GitHub Release publication are prepared in files but have not run.
- The Intel slice is built and inspected locally; native Intel execution is delegated to the prepared future CI matrix. Minimum macOS 14 runtime compatibility still requires testing on that OS. The configured hosted toolchain is Xcode 26.6; the current local run used Xcode 27.1.
- The app harness uses SIGTERM, not the normal menu-Q action. It does not assert visual scrollback, authenticated coding-agent TUIs, every tab-close error path, SSH, forge mutations or full feature parity.
- REA's earlier exact-window observation was denied Screen Recording permission. No screenshot/AX result or broader capture fallback was obtained. The retained diagnostic and REA packaged-app findings remain in the original local workspace under ignored docs/evidence; they are separate from ordinary harness evidence.
- A bounded source inspection found no app-owned analytics/telemetry/activation client. It does not establish the network behavior of commands, agents or OS services launched by the user.

Git history tracks the baseline and release-hardening source. Generated app bundles, archives, private investigation output and signing material are excluded. No remote was created or pushed.

## Named scripts — 2026-11-02

Inspected the pinned Supacode source and documented [its categories, project-specific commands, execution path and hooks](SUPACODE-SCRIPTS.md). Implemented Grove-owned categories/examples, editable metadata and scope, repository config review/import, primary shortcuts, tab reuse, explicit stop/restart and printed exit codes. `GROVE_RUN_GUI_CHECKS=1 bash scripts/check.sh` passed Git/state/script/release-policy/screen fixtures, a host arm64 release build, bundle/signature validation and actual packaged-app relaunch. The relaunch retained shell PID 15160, stable layout IDs, no startup-command replay and one matching screen session. The script check executes real zsh with quoted/multiline commands, worktree cwd/environment and exit 7. Final config symlink/bounded-read and duplicate-name palette corrections were checked and rebuilt afterward. This task does not claim a fresh universal release, hosted CI execution, or automated interaction coverage for the new Settings/Stop/Restart/shortcut controls. Those manual scenarios are in [Testing](TESTING.md); automatic lifecycle hooks and structured script state remain outside this implementation.

## External Open menu — 2026-11-02

Added the requested VS Code/Xcode/Terminal/Finder launcher beside Scripts, with remembered global selection, installed-app detection and launch error handling. The host arm64 packaged app rebuilt and passed bundle/signature validation. `OpenTargetCheck` passed real temporary-directory checks for quoted/spaced paths, workspace/project/Package.swift precedence, exclusion of internal project workspaces and hidden/dependency/deep/symlink targets, and missing-path rejection. The fixture compares canonical paths to account for macOS's `/var`/`/private/var` alias. The packaged-app relaunch check passed again with shell PID 42129, stable layout IDs, no command replay and one screen session. External app window contents and menu click interactions remain manual validation; their checklist is in [Testing](TESTING.md).
