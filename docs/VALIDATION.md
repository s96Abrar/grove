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
- Release-policy fixtures passed matching immutable tag handling and rejection of invalid/mismatched tags, dirty source and missing signing/notarization configuration.
- Actionlint 1.7.12 passed the prepared workflows. Its downloaded macOS binary was verified against the pinned upstream release SHA-256. YAML parsing, immutable action-pin checks, shell syntax and documentation-link checks also passed. No release schedule trigger is present.

Commands: `make check`, `make lint`, and `GROVE_ARCHS="arm64 x86_64" python3 scripts/release.py --mode local`. The consolidated checks can reuse an already built universal bundle with `GROVE_SKIP_BUILD=1 GROVE_RUN_GUI_CHECKS=1 bash scripts/check.sh`.

## Real build failures corrected

The default Swift 6.4 swiftbuild engine compiled a dependency build-time helper for the destination Intel CPU, which could not run on the host without Rosetta. Explicit minimum-OS triples and SwiftPM's native engine keep build helpers host-native. Per-architecture scratch paths prevent cross-architecture cache collisions, and compiler parallelism defaults to two jobs after a resource-exhaustion error. No Rosetta install or sandbox disable was used. A source edit invalidated one in-flight build; all final application source was built together afterward. See RELEASING.md for the native-engine deprecation/toolchain upgrade caveat.

## Release limits

- No valid Developer ID signing identity is available on the current Mac. Apple submission, notarization, stapling, Gatekeeper acceptance of a public signed build and CI signing-key import/cleanup have not been executed. Local output is explicitly ad-hoc, not a public notarized release.
- No Git remote exists. Hosted CI, protected tag/environment settings and GitHub Release publication are prepared in files but have not run.
- The Intel slice is built and inspected locally; native Intel execution is delegated to the prepared future CI matrix. Minimum macOS 14 runtime compatibility still requires testing on that OS. The configured hosted toolchain is Xcode 26.6; the current local run used Xcode 27.1.
- The app harness uses SIGTERM, not the normal menu-Q action. It does not assert visual scrollback, authenticated coding-agent TUIs, every tab-close error path, SSH, forge mutations or full feature parity.
- REA's earlier exact-window observation was denied Screen Recording permission. No screenshot/AX result or broader capture fallback was obtained. The retained diagnostic and REA packaged-app findings remain in the original local workspace under ignored docs/evidence; they are separate from ordinary harness evidence.
- A bounded source inspection found no app-owned analytics/telemetry/activation client. It does not establish the network behavior of commands, agents or OS services launched by the user.

Git history tracks the baseline and release-hardening source. Generated app bundles, archives, private investigation output and signing material are excluded. No remote was created or pushed.
