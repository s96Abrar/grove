# UI/UX Review — 2026-11-23

Scope: full app UI pass using the `ui-ux-pro-max` skill (`nextlevelbuilder/ui-ux-pro-max-skill`, installed to `~/.claude/skills/ui-ux-pro-max`), focused on the SwiftUI stack detected from `Package.swift`.

Changes are **uncommitted**. The patch is at `docs/patches/ui-review-2026-11-23.patch`.

## Method

1. Read the main surfaces: `Grove.swift` (sidebar, content header, session tabs, terminal panes, worktree rows, performance pill, banners, remove dialog), `Settings.swift`, `Scripts.swift` (settings tab), `FileBrowser.swift`, `OpenMenu.swift`.
2. Scanned every source file for icon-only controls without an accessibility label.
3. Queried the skill for guidance:
   - `--stack swiftui`: "form text wrap fixed width overflow" → frame modifiers, use `Form` for settings, Dynamic Type.
   - `--domain ux`: "settings form helper text wrap" → form labels, error and feedback guidance.
4. Applied the fixes below, then built with `swift build`.

`DiffView.swift` (466 lines) was scanned by grep only. It was not read in full.

## Findings and changes

| # | Severity (skill) | Where | Finding | Change |
|---|---|---|---|---|
| 1 | High (Settings overflow, reported) | `Settings.swift` General tab | Form nested in `ScrollView` got unbounded height; captions didn't wrap, so content was wider than the 660pt window and clipped on both sides. | Removed outer `ScrollView`; `.fixedSize(horizontal: false, vertical: true)` on the three caption texts. Re-indented the Form body. |
| 2 | Critical (Accessibility, skill priority 1) | `Grove.swift` toolbar | "Reveal in Finder", "Browse files" icon buttons had only a tooltip; VoiceOver read the SF Symbol name. | Added `.accessibilityLabel`. |
| 3 | Critical (Accessibility) | `Grove.swift` session tabs | Tab close button had no label or tooltip. | Added label and `Close tab` tooltip. |
| 4 | High (Touch target) | `Grove.swift` session tabs | Tab close glyph is 8pt with no hit area. | Frame 18×18 with `contentShape` for a usable hit area. |
| 5 | Critical (Accessibility) | `Grove.swift` session tabs | "New tab" and split-menu icon buttons: tooltip only / no label. | Added `.accessibilityLabel` (and tooltip for split menu). |
| 6 | High (Forms/feedback) | `Grove.swift` create-worktree sheet, rename-branch sheet, rename-tab sheet | Cancel did not respond to Esc; primary actions had no default-action binding. | `.keyboardShortcut(.cancelAction)` on Cancel; `.keyboardShortcut(.defaultAction)` on Rename/Save. The create sheet's primary button is left unchanged: it already submits via `onSubmit`, and a default binding could double-fire. |
| 7 | Critical (Accessibility) | `FileBrowser.swift` | Parent-folder and reload icon buttons had no label. | Added `.accessibilityLabel`. |
| 8 | Critical (Accessibility) | `Scripts.swift` script list | Run / move-earlier / remove icon buttons had tooltips only. | Added `.accessibilityLabel`. |

## Verification

- `swift build`: passes after all changes.
- `git apply --check --reverse docs/patches/ui-review-2026-11-23.patch`: the patch matches the working tree.
- Not verified visually. The app was not launched, so the layout result of changes 1 and 4 is unconfirmed against a screenshot.

## Not changed (open items)

- **Fixed window frame** `TabView { … }.frame(width: 660, height: 640)` in `Settings.swift`. Skill says avoid fixed sizes for responsive content. Kept as a design choice; changing it is a product decision.
- **Placeholder-only text field** "Find a worktree…" (`Grove.swift`) and "New branch name" / "Script name" fields rely on placeholders. Skill flags placeholder-only inputs. Needs a visible label or `accessibilityLabel` decision.
- **Icon picker** in Scripts shows raw SF Symbol names (e.g. `terminal`) as labels. Usability issue; needs a naming map.
- **`DiffView.swift`** only grep-scanned. Full review pending.
- **Help tab text** lists "Command palette ⌘K or ⇧⌘P"; the menu bar shows ⌘K and ⇧⌘P as separate items. Consistent enough, not changed.
- **Dynamic Type** (skill priority 1 for iOS): Grove is macOS. Fixed font sizes in the sidebar and header are a deliberate density choice; not changed.

## Applying the patch

```sh
git apply docs/patches/ui-review-2026-11-23.patch
```

No commit has been made.
