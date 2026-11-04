# Validation — Grove 0.3.0

Local host: Apple Silicon, macOS 27, Swift 6.4 / Xcode 27.1. This records bounded observations, not a claim that every supported system or Supacode feature has been verified.

## UI/UX branch corrective review — 2026-11-04

Reviewed both commits on `uiux-refactor` against `main`, including the project documentation. The initial actual-module regression run reproduced 10 assertion failures across five of six cases. After the corrections, the expanded suite passed all 11 cases. These cover real Git cleanup/removal, locked checkouts and hook-created commits, session identity and removal races, diff paths/metadata/numbering, triage and accessibility policy. A separate check passed actual profile transition callbacks and SDK thermal notification delivery. See [the claims, corrections and evidence](UIUX-BRANCH-REVIEW.md).

The final `GROVE_RUN_GUI_CHECKS=1 bash scripts/check.sh` passed all checks, rebuilt the host arm64 app, verified bundle integrity and hardened ad-hoc signing, and exercised installer replacement/rollback and actual packaged-app relaunch. The app retained shell PID 10384, stable layout IDs and one tmux session, without startup replay or GNU screen context. Workflow lint and whitespace checks passed. This run does not establish a fresh universal release, hosted CI execution, or manual palette/IME, visual rendering and profile-transition UI acceptance. Those boundaries remain in [Testing](TESTING.md). The accepted non-notarized distribution policy is unchanged.

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

## Close a terminal split — 2026-11-02

The terminal pane header lacked an individual close action. Added an accessible **×** control for split panes, confirmation, exact-pane session cleanup and recursive layout collapse. The operation captures its originating worktree/tab, serializes pane closes within that tab, re-reads state after asynchronous cleanup and preserves metadata on cleanup failure. The final pane is retained; whole-tab closure remains available. `StateCheck` first failed on the missing pane-removal operation, then passed removal of every position in a nested mixed-axis layout, sibling promotion/orientation, surviving tab/pane identities, persistence round trips, legacy layouts and last/unknown-pane guards. The host arm64 release build and ad-hoc bundle validation passed. Packaged-app termination/relaunch also passed with shell PID 48732, stable layout IDs, no command replay and one matching screen session. Pane-button/confirmation interaction and live sibling-counter continuity remain manual scenarios in [Testing](TESTING.md), not automated UI claims.

## Repository expand/collapse — 2026-11-02

Added native disclosure controls to repository and plain-folder headings. Collapsed paths persist in workspace metadata; older metadata defaults to expanded headings. Search uses temporary expansion state so matches in collapsed repositories can be shown without overwriting saved choices. Only sidebar rows are hidden: selection and terminal session ownership remain unchanged. `StateCheck` passed collapsed-state round-trip and absent-field migration alongside existing state/layout checks. The host arm64 build and ad-hoc bundle validation passed. The isolated packaged-app relaunch check passed with shell PID 60718, stable layout IDs, no startup replay and one matching screen session. Disclosure clicks, search interactions and live counters while collapsing are manual scenarios in [Testing](TESTING.md); no automated UI interaction result is claimed.

## Footer cleanup and shortcut help — 2026-11-02

The user confirmed removal of both bottom footer strips: the sidebar tagline and the terminal's isolated-worktree/shortcut strip. Their dividers were removed with them. Settings now includes a scrollable Help tab listing supported shortcuts, modifier symbols and terminal/script context notes. Shortcut entries were compared with the registered actions; the user guide was updated. The host arm64 release build, bundle metadata and hardened ad-hoc signature verification passed. This small presentation change adds no new test suite; visual Settings interaction remains manual validation.

## Tmux persistence and Gemini warning — 2026-11-02

The installed Gemini CLI 0.66.0's GNU screen detector checks STY. The user chose tmux persistence; Homebrew tmux 3.8 was installed locally. New panes now use a separate Grove tmux server and bundled configuration, while live screen sessions are retained for reattachment. tmux is an external runtime dependency; no tmux executable is bundled. Package verification requires the configuration file. The CI quality matrix installs tmux; hosted execution remains unverified without a remote.

The final host arm64 build passed. `GROVE_SKIP_BUILD=1 GROVE_RUN_GUI_CHECKS=1 bash scripts/check.sh` passed Git, saved-state, script, external-open, release-policy, legacy screen and new tmux fixtures, bundle validation and actual packaged-app termination/relaunch. The tmux fixture retained shell PID 99237, observed no STY and TERM=tmux-256color, passed Ctrl-B, retained per-pane context across a shared server, preserved a sibling through cleanup and reattached a legacy screen shell without replacement. The app harness retained shell PID 99343, stable layout IDs and exactly one tmux session, with no GNU screen context and no startup command replay. Actionlint and Python syntax checks passed.

The first combined backend fixture timed out while waiting for its legacy screen client before draining the PTY; the corrected fixture drains output and then passed in isolation and in the full run. No authenticated Gemini session or complete visual/key-protocol coverage is claimed. Existing screen-backed panes still have screen's limitations; users should start Gemini in a fresh tab after reopening the rebuilt app. See [compatibility evidence and migration](TERMINAL-COMPATIBILITY.md).
