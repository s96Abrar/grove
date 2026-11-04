# Changelog

## Unreleased

- Terminal font guard: SwiftUI update passes no longer re-assign the terminal font on every state publish, avoiding SwiftTerm FontSet rebuilds, cell-metric recomputes, selection clears and full re-renders for every open terminal.
- Terminal font glyph fallback: Nerd Font/Powerline prompt icons render from an installed patched font when the selected terminal font lacks them.

## 0.3.0 — release preparation

- Original Grove app icon with full macOS icon sizes and source artwork.
- Versioned, staged app packaging with build provenance, license notices and hardened runtime.
- Workspace-state validation, legacy migration, last-good backup recovery and preservation of unreadable data.
- Tab startup commands are transient; restoration never automatically repeats an old script.
- Confirmed tab closure ends sessions; regular app quit preserves persistent shells.
- Active-tab selection is saved; cold-start deeplinks wait for workspace loading.
- Worktree removal protects ignored files as well as tracked/untracked changes.
- Local delivery ZIPs with checksums and round-trip validation.
- Tag-only ad-hoc release pipeline, prepared native-architecture CI and local Git history.

Apple signing/notarization are intentionally excluded by user policy. Hosted CI and publication have not run; no remote exists. See docs/RELEASING.md for prerequisites and remaining validation.

## 0.2.0

Independent SwiftUI workspace, embedded SwiftTerm PTYs, screen-backed persistent sessions, worktrees, nested splits, scripts, palette, files, Git review and basic CLI/deeplinks. No telemetry or activation.
