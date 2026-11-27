# Release plan

This is the plan for what ships next and how. The release *process* (gates, scripts, workflows) is in [RELEASING.md](RELEASING.md). Readiness findings are in [lifecycle status](lifecycle/status.md).

Last updated: 2026-11-27.

## Where things stand

| Item | State |
|---|---|
| Version in `release.json` | `0.3.0`, build `4` |
| Tags / GitHub releases | **v0.3.0** tagged and published on 2026-11-26 ([release](https://github.com/s96Abrar/grove/releases/tag/v0.3.0)). |
| `CHANGELOG.md` | `0.3.0 — 2026-11-26` section, plus an **Unreleased** list for the next release. |
| CI on `main` | Quality checks (macOS build, tests, packaging, GUI relaunch) plus security checks (OSV vulnerability scan, gitleaks, Dependabot). |
| Readiness | Lifecycle gate: **no Blockers, no open Should-fix items.** Two owner decisions remain (S-2, P-4); neither blocks a release. |
| Distribution | Ad-hoc-signed and not notarized, by accepted policy ([AGENTS.md](../AGENTS.md)). |

## Next release: v0.4.0 (in progress)

Features are added one PR at a time, each merged after CI. Merged items move to the CHANGELOG's Unreleased list.

1. Setup scripts that run when a worktree is created — **done**.
2. Optional branch deletion when removing a worktree — **done**.
3. Git status markers in the file browser — **done**.
4. Cancellable fetch-before-create — **done**.
5. Command palette: keep the arrow-key selection scrolled into view, plus Home/End — **done**. (Arrow-key selection itself already existed.)
6. Agent "awaiting input" detection — **done**.
7. Notifications for item 6 — **done**.
8. Opt-in PR status badge in the sidebar.

Release criteria, steps and known limitations are the same as for v0.3.0 below; add a smoke test for each new feature.

## v0.3.0 (first public release, published 2026-11-26)

**Recommendation:** publish the first tagged release as **v0.3.0**. No 0.3.0 artifact exists anywhere, so there is nothing to conflict with. Fold the Unreleased notes into the 0.3.0 section rather than skipping to 0.4.0.

If you would rather keep "0.3.0" as the historical preparation milestone, use **v0.4.0** instead: set `"version": "0.4.0"` in `release.json` and keep 0.3.0's notes as they are. Everything below works the same with either number.

### Scope

Everything already on `main`:

- Embedded terminals with tmux persistence, worktrees, tabs and nested splits, scripts, command palette, file browser, Changes (diff) view, opt-in GitHub lookup, CLI and `grove://` links.
- Performance work from the Unreleased list (fewer redraws, memoized diffs, gated polling).
- Security fixes: confirmation for `grove://` actions and for opening executable files, Dependabot, OSV and secret scanning.
- Privacy fixes: Reset deletes saved data, and "Remove from Grove" works per repository.
- UI states: clone progress and Cancel, validation as you type, plain-language errors, empty and no-results states.

Nothing new is added for this release. It is a release of what is merged.

### Release criteria

All must hold on the commit that gets tagged:

- [ ] Quality checks and Security checks are green on `main`.
- [ ] `docs/lifecycle/status.md` shows zero Blockers.
- [ ] Manual smoke test on an Apple Silicon Mac with the packaged app (`make package`), covering:
  - [ ] add a repository, create, rename and remove a worktree, and "Remove from Grove" on a repository
  - [ ] terminal tabs, splits, Quit, then relaunch with sessions restored
  - [ ] clone with Cancel; clone with a bad URL (inline error)
  - [ ] a `grove://open` link from a browser, which must show the confirmation
  - [ ] a `.command` file in the file browser, which must ask first
  - [ ] Settings → Reset Workspace Metadata
  - [ ] light and dark mode; VoiceOver on the sidebar, tab bar and new dialogs
  - [ ] palette focus and arrow keys, including with an input method active
- [ ] `scripts/perf.py` run on the release candidate, with numbers noted in the release notes (see the README's Performance section).
- [ ] Known limitations written into the release notes (below).

### Known limitations to state in the release notes

- Ad-hoc signed, not notarized: macOS will ask for confirmation on first open. This is by design.
- The Intel (x86_64) slice is built and verified but has not been run on an Intel Mac.
- The macOS 14 minimum is declared but has not been tested on macOS 14.
- Not at feature parity with Supacode. See [feature matrix](FEATURE-PARITY.md).

### Steps

1. **Freeze.** Merge nothing but release-prep changes until the tag is pushed.
2. **Release-prep PR:**
   - In `CHANGELOG.md`, rename the section to `## 0.3.0 — <date>`, merge the Unreleased entries into it, and drop "release preparation" and the "no remote / hosted CI has not run" sentence.
   - Bump `build` in `release.json` (to `4`), and `version` if you chose 0.4.0.
   - Correct the out-of-date statements in `README.md` and `docs/RELEASING.md` that say no remote exists and hosted CI has never run.
   - Merge once CI is green.
3. **Smoke test** the `Grove-local-macos-26` artifact from that merge's CI run against the criteria above.
4. **Optional:** set required reviewers on the `release` environment (Settings → Environments → release), so publishing waits for your approval.
5. **Tag and push** from an up-to-date `main`:
   ```sh
   git tag -a v0.3.0 -m "Grove 0.3.0"
   git push origin v0.3.0
   ```
   `release.yml` re-runs the quality checks, builds the universal app, validates the archive and publishes a GitHub Release with the ZIP, `SHA256SUMS` and `release-manifest.json`.
6. **Verify the published release:**
   - Download the ZIP and run `shasum -a 256 -c SHA256SUMS`.
   - Run `codesign --verify --deep --strict Grove.app`.
   - Check that the manifest says `"notarized": false` and `"distribution": "tagged-adhoc"`.
   - Open the app once.
7. **After the release:**
   - Add a fresh `## Unreleased` heading.
   - Record the release in [VALIDATION.md](VALIDATION.md).
   - Update this plan for the next version.

Tags and releases are immutable. A mistake is fixed with a new patch release (`v0.3.1`), never by moving a tag.

## Versioning and cadence

- Releases are **tagged only**: no scheduled releases and no automatic version bumps ([AGENTS.md](../AGENTS.md)).
- Before 1.0: **minor** (`0.x.0`) for new features or behavior changes, **patch** (`0.x.y`) for fixes only. `build` increases by one for every release.
- Release when there is a meaningful set of merged changes. Security fixes get a patch release as soon as they merge.

## Candidates for the following release

Not committed; pick from these after the first release ships.

- **Owner decisions:**
  - S-2: whether background `git status` may run programs a repository configures.
  - P-4: whether workspace data stays in system backups.
- Make fetch-before-create cancellable, and stream `git worktree add` output into a tab.
- Post-create setup hooks for new worktrees.
- Agent "awaiting input" detection (the triage status slot already exists).
- Cursor-blink suppression in the Efficient profile.
- Feature-parity gaps from the [feature matrix](FEATURE-PARITY.md): branch grouping in the sidebar, archived-worktree expiry, custom shortcuts, terminal theme sync.
- Moving SwiftTerm from a revision pin to a version tag, so Dependabot can update it.
- Testing on an Intel Mac and on macOS 14.
