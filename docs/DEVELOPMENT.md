# Development and operations

## Build requirements

The original implementation targeted macOS 14+ with Swift tools 5.9+ and system Git. The expanded package now declares Swift tools 6.2 and the MIT SwiftTerm dependency pinned to revision `e213ebb5cc7005e1b9e4629ae97bf921808f683a`; consult `Package.swift` for current inputs. The recorded local build used Swift 6.4 / Xcode 27.1 on Apple Silicon. New dependency requirements must be recorded when introduced. `Package.swift` and any resolved package lockfile are the authoritative dependency inputs.

From the project root:

```sh
swift build
bash scripts/build-app.sh
open dist/Grove.app
```

The script performs a release build, resolves SwiftPM’s executable directory, creates `dist/Grove.app`, writes Info.plist and applies a local ad-hoc signature. Build intermediates are under `.build/`. Generated bundles are under `dist/`. Both are ignored by the supplied `.gitignore`.

A package build is not a packaged-app launch check. Use [testing](TESTING.md) and retain actual outcomes in [validation](VALIDATION.md).

## Storage and effects

Current workspace state is JSON-encoded Codable data in the application’s UserDefaults `workspace.v2` key. It includes roots, selected worktree, tabs/panes, recursive split layout, pins, archives and scripts. Appearance/font/persistence/GitHub opt-in and base-ref/fetch-before-create preferences use AppStorage. WorkspaceState.swift validates saved data and retains a last-good backup plus unreadable metadata. Corruption without a valid backup blocks saves until confirmed recovery. The original repositories key is used only when there is no v2 state.

New Git checkouts live under a sibling `.grove-worktrees/<repository>/` directory. Persistent terminal shells run in system screen sessions named `grove-<pane UUID>`. Screen retention is separate from saved app metadata: confirmed tab closure ends its screen session before removing metadata. Use `screen -list` to inspect such orphans; end only deliberately identified sessions. Grove’s explicit end-sessions-and-quit action targets saved IDs and surfaces cleanup failures.

Git probes read local state; worktree creation changes refs/checkouts. Optional fetch-before-create runs git fetch --prune against configured remotes. Branch rename changes a ref. Confirmed clean worktree removal deletes its checkout, preserves the branch and clears its saved workspace metadata; main/dirty checks precede removal. Clone contacts the provided Git remote. Optional manual GitHub lookup invokes local authenticated `gh`. User commands/scripts and shell startup files run with the user’s permissions and may access files or network. See [privacy](PRIVACY.md).

Do not delete a managed checkout using a generic file-manager operation when Git should remove its metadata. Do not reset repositories, purge caches or terminate unrelated screen sessions as generic repair steps.

## Troubleshooting

| Symptom | Check/action |
|---|---|
| Swift build cannot write compiler/SwiftPM cache | Inspect the actual sandbox/cache failure; grant required build access through the host approval flow. |
| New branch fails | Inspect the Git error; a Git repository needs a commit and a valid, unused branch name. Plain folders cannot create worktrees. |
| Created directory is not selected | Compare Git’s canonical path to app identity; macOS `/var` and `/private/var` aliases need consistent handling. |
| Embedded pane reports launch failure | Check `/usr/bin/screen`, shell configuration and reported process failure. Disable persistence for a new test pane to isolate daemon behavior. |
| Terminal appears detached or already attached | Inspect the exact `grove-<pane UUID>` session; persistence uses screen detach/reattach, not command replay. Avoid terminating other users’ sessions. |
| Closing a tab leaves a process | Confirmed close in 0.3 ends that tab’s sessions; older versions may have left detached sessions. Use exact-session cleanup deliberately. |
| Agent unavailable | Check installed executable and login-shell PATH. Grove adds common Homebrew/local directories but does not install/authenticate agents. |
| Untracked file has no diff | Expected: untracked paths are status entries, not tracked diff contents. |
| PR query fails | Confirm GitHub opt-in, `gh` installation/authentication and a PR associated with selected branch. Lookup is manual, not live integration. |
| File not shown in browser | Hidden entries are skipped; use terminal/Finder for complete filesystem access. |
| Repository moved or removed | Inspect saved root and actual directory; preserve repository data while correcting workspace metadata. |
| REA tools absent | MCP registration and active client connection are distinct; supported CLI operations were used for retained findings. |
| REA native decompilation unavailable | No native provider was installed; resource/architecture evidence does not substitute for decompiled behavior. |

## Distribution and updates

The accepted release policy uses ad-hoc signatures for local and tagged releases. Apple signing/notarization are intentionally excluded and are not readiness blockers. Releases still require stable identity, intended architectures, integrity/archive checks and validation on supported machines. Automatic updates additionally require a Grove-controlled signed feed, update keys and release process. These are real release dependencies, not buttons that can be completed by reusing Supacode’s production services.

Document and preserve license notices for dependencies. The selected direction is independent: do not adopt Supacode code or assets. Retain the MIT license and copyright notices for SwiftTerm and notices required by any resolved transitive dependencies. The independent baseline investigation did not copy Supacode’s implementation or artwork.

## Maintenance

When adding a feature, update its coverage row, user-facing instructions, storage/dependency effects and observed validation. Keep proposed design separate from shipped behavior. Record upstream source changes by commit rather than letting moving `main` links change the meaning of older evidence.

## Version 0.3 release tooling

Use make check for the complete local check path and make package for a local-only archive. Version metadata is in release.json. Universal builds use GROVE_ARCHS="arm64 x86_64". The source icon renderer is scripts/render-icon.swift; Resources/AppIcon.png is the committed raster master. No image-generation service is used. A fresh staging bundle is signed and verified before replacing the generated app, avoiding in-place changes to old bundle files. Complete credentials, pipeline and no-remote status are documented in [Releasing](RELEASING.md).
