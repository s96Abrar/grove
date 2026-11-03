# Grove — UI/UX Refactor Implementation Plan

**Companion to:** `docs/UIUX-AUDIT.md` (friction audit, file:line citations). This doc specifies the concrete changes, acceptance criteria, and risks for each phase. **Council review:** see `docs/UIUX-PLAN-REVIEWS.md` (generated after council verdicts; blocking change requests are folded into §8 below).

**Policy constraints (AGENTS.md):** no telemetry/activation, preserve dependency notices, releases tagged only, ad-hoc signing is accepted policy. All changes are local MIT-licensed source changes; no release/signing work involved.

---

## 1. Phase 1 — P0 correctness (ship first, no behavior regressions allowed)

### 1.1 Kill tmux sessions on worktree removal
- **Files:** `Sources/Grove/Workspace.swift` (`remove`, ~:188-196), `Sources/Grove/Session.swift`.
- **Change:** replace `sessions[pane.id]?.detach()` with the same teardown `closeTab` uses: terminate the PTY and `tmux kill-session` (via existing `endSession` path, `Workspace.swift:240-247`), for every pane of every tab whose root matches the removed worktree. Keep the rest of removal flow (git worktree remove, hard dirty-block) untouched.
- **Acceptance:** after `Workspace.remove`, `tmux -L grove list-sessions` contains no session for the removed panes; existing removal behavior (dirty block, branch kept) unchanged.
- **New test:** extend `Checks/` with a removal-session-cleanup check (spawns a pane, removes worktree, asserts no matching tmux session).

### 1.2 Theme-aware terminal background
- **Files:** `Sources/Grove/Session.swift:14-20`, `Sources/Grove/Grove.swift` (appearance wiring), `Sources/Grove/Settings.swift`.
- **Change:** derive `terminal.nativeBackgroundColor` from the active `appearance` AppStorage value: dark → current dark NSColor; light/system-light → `NSColor.textBackgroundColor` (respects user terminal theme later); system-dark → dark value. Update on `colorScheme` change (invalidate/re-apply to existing `EmbeddedTerminal` views).
- **Acceptance:** switching Appearance Dark ↔ Light re-colors terminal surfaces; no hardcoded dark-only surface.

### 1.3 Light-mode chrome seams
- **Files:** `Sources/Grove/Grove.swift:54,122,157,~213`.
- **Change:** replace `Color.white.opacity(0.08)` tab pill with `Color.primary.opacity(0.08)`; route sidebar/panel hardcoded RGBs through `Color(nsColor:)` equivalents that track appearance (interim until Phase 3 token layer replaces them).
- **Acceptance:** light/system appearance shows visible tab selection and correct sidebar contrast; dark unchanged visually.

### 1.4 Launch-failure status dot
- **Files:** `Sources/Grove/Grove.swift:276-287` (`TerminalPane` header), `Sources/Grove/Session.swift:60-62`.
- **Change:** classify `session.state.hasPrefix("Launch failed")` and non-zero `"Exited N"` as failure rendering (red/high-contrast symbol) instead of falling through to green.
- **Acceptance:** failing PTY launch and `Exited 1` show failure styling; `Exited 0` shows neutral/completed styling.

## 2. Phase 2 — Keyboard-first ergonomics & focus discipline

### 2.1 Deterministic focus restoration
- **Files:** `Sources/Grove/Workspace.swift` (model), `Sources/Grove/Grove.swift` (TerminalPane, sheets/alerts).
- **Change:** add `lastFocusedPaneID: Pane.ID?` to the model; `TerminalPane` records it on becoming first responder (reuse `window?.firstResponder === view` predicate, `Workspace.swift:98`). On sheet/alert/dialog dismissal (`onDismiss`), re-activate the recorded pane's terminal view (via `NSApp.keyWindow` → makeFirstResponder on the terminal view looked up through `saved.tabs`).
- **Acceptance:** open create sheet → dismiss → terminal focus restored without mouse; same for error alert dismissal.

### 2.2 Non-modal background errors
- **Files:** `Sources/Grove/Workspace.swift:146,166,175-187` (error funnel), `Sources/Grove/Grove.swift:184` (alert), new banner strip.
- **Change:** add `backgroundError: String?` (distinct from user-action `error`); poll/reload failures set `backgroundError` → dismissible non-modal banner below the toolbar. User-initiated failures keep the existing modal alert.
- **Acceptance:** a simulated poll failure shows banner, never steals key focus; create/remove failures still alert.

### 2.3 Command Palette upgrade
- **Files:** `Sources/Grove/Settings.swift` (palette), `Sources/Grove/Grove.swift:16`.
- **Change:** (a) ⌘K as an additional menu shortcut; (b) focus the query field on appear; (c) arrow-key/`onMoveCommand` selection with highlighted row; Return executes selection (not just first); (d) right-aligned shortcut hints per row (route `Action.key`, `Settings.swift:46`); (e) busy-gate "Create worktree" on `model.busy` (parity with sheet, `Grove.swift:181`); (f) seed palette rows from the same action list that backs the new menu items (single source of truth).
- **Acceptance:** ⌘K or ⇧⌘P opens palette; typing lands in query; ↑/↓ + Return executes any action; rows show shortcut glyphs when they exist.

### 2.4 Missing core shortcuts (menu-backed, discoverable)
- **Files:** `Sources/Grove/Grove.swift` (CommandMenu/CommandGroups), `Sources/Grove/Workspace.swift` (wrappers).
- **Change:** menu items with key equivalents: ⌘W close pane/tab (existing confirmation preserved), ⌘D split vertically, ⇧⌘D split horizontally, ⇧⌘] / ⇧⌘[ cycle tabs, ⇧⌘C copy worktree path, ⇧⌘B copy branch name; promote worktree actions (archive, pin, rename, remove, open in IDE) into CommandGroup menus; promote hidden ⌘N (`Grove.swift:119`) into the menu.
- **Acceptance:** every listed action executable with zero mouse and visible in the menu bar with its glyph.

### 2.5 Active-pane indicator
- **Files:** `Sources/Grove/Grove.swift` (`TerminalPane`).
- **Change:** track `isKey` via `window?.firstResponder === view`; render a 1-pt accent border (pane outline). No animation (keeps zero-cost baseline; Phase 3 adds optional springs).
- **Acceptance:** in a split, exactly the focused pane shows the accent edge; unfocused panes recede.

### 2.6 Jump-to-next-attention (⌘⇧A)
- **Files:** `Sources/Grove/Grove.swift` (menu + shortcut), `Sources/Grove/Workspace.swift` (`jumpToNextAttention()`).
- **Change:** iterate panes via `saved.tabs`; select first whose session state is failed (extended to `awaitingInput` once Phase 4 lands); restore focus per §2.1. Sidebar badge marks destinations.
- **Acceptance:** with two worktrees, one failed, ⌘⇧A switches selection + refocuses its pane; pressed again, it cycles.
- **Dep:** state classification from §1.4; full semantics completed by Phase 4 rollup.

## 3. Phase 3 — Performance profile token layer

### 3.1 `PerformanceProfileManager`
- **Files:** new `Sources/Grove/PerformanceProfile.swift`.
- **Change:** `enum PerformanceProfile { auto, highPerformance, efficient }` persisted via `@AppStorage("performanceProfile")`; singleton `ObservableObject` computing `effectiveTier` (`.efficient` when auto-triggers hit) from `NSProcessInfo.processInfo.isLowPowerModeEnabled`, `thermalState ≠ .nominal`, window-not-key observation, and a11y preferences; `activeTriggers: [String]` records *why* (e.g. "Low Power Mode enabled"). Observed triggers via KVO/NotificationCenter on `NSProcessInfo` + `NSWorkspace.didWakeNotification` (also feeds §5.3 wake refresh).
- **Acceptance:** toggling Low Power Mode flips effective tier in Auto; manual overrides always win; triggers list non-empty when Auto downgrades.

### 3.2 `AppTheme` + ViewModifiers
- **Files:** new `Sources/Grove/AppTheme.swift`; migrate hardcoded colors from `Grove.swift:54,64,122,157,~213` and `Session.swift:20`.
- **Change:** `AppTheme` resolved per tier + colorScheme + a11y prefs:
  - **HighPerformance tier:** adds `Material` (`ultraThinMaterial` sidebar/panels) and allows springs (response 0.22, damping 0.88) for palette/sheet/split transitions. Terminal surface stays opaque (readability).
  - **Efficient tier (or a11y reduceMotion/reduceTransparency):** opaque colors, `transaction { $0.animation = nil }`, static SF Symbols instead of any spinner.
  - `ThemedSurface` ViewModifier selects material vs opaque; `ProfiledAnimation` gates springs; `ProfiledSpinner` renders `ProgressView` vs static glyph. All a11y prefs force the Efficient treatment regardless of tier.
- **Acceptance:** switching profile tier changes materials/animations atomically; reduceTransparency forces opaque; reduceMotion forces instant transitions; zero `.repeatForever`/`TimelineView` anywhere (grep-gate in `Checks/`).

### 3.3 Settings + status pill
- **Files:** `Sources/Grove/Settings.swift` (new picker), `Sources/Grove/Grove.swift` (sidebar header pill + popover).
- **Change:** "Visual profile: Auto (System-Aware) | High Performance | Efficient" picker with explanatory caption; toolbar/sidebar status pill showing `⚡ High Perf` / `🍃 Efficient • <primary trigger>`; pill opens a popover with mode selector, active triggers, and lightweight metrics (active agent count from §4 rollup, suspended surfaces count, target FPS cap).
- **Acceptance:** pill reflects live tier; popover selector updates tier instantly; metrics match actual pane counts.

### 3.4 Terminal polish gates
- **Files:** `Sources/Grove/Session.swift`, `PersistentTerminal.swift`.
- **Change:** Efficient tier forces static (non-blinking) cursor and disables optional smooth-scroll behaviors; HighPerformance may enable SwiftTerm cursor blink/ligature pass-through via settings. Debounce `state` re-publishes (`Session.swift:62`) to avoid header thrash.
- **Acceptance:** no per-frame work in Efficient tier (verifiable via CPU sampling in Check evidence notes); smooth behaviors only in HighPerformance.

---

## 4. Phase 4 — Multi-agent triage

### 4.1 `WorktreeStatus` model + rollup
- **Files:** new `Sources/Grove/WorktreeStatus.swift`; `Sources/Grove/Session.swift` (state parsing), `Sources/Grove/Workspace.swift` (rollup).
- **Change:** `enum WorktreeStatus { awaitingInput, failed, running, completed, idle }` with SF Symbol + semantic color + accessibility label per case. Parse exit codes out of `Session.state` strings ("Exited N", "Launch failed: …") into structured values at assignment time (keep `state` string for display compat during migration). `Workspace.status(for:)` rolls up sessions per worktree with precedence `awaitingInput > failed > running > completed > idle`.
- **Acceptance:** unit-checkable mapping: Exited 1 → failed, Exited 0 → completed, Program active → running, Shell → idle.

### 4.2 Sidebar row redesign
- **Files:** `Sources/Grove/Grove.swift:92-101` (rows), `Sources/Grove/Workspace.swift`/`Git.swift` (diff data).
- **Change:** two-line row: status symbol (never color alone) + monospace branch + `+adds −dels` monospacedDigit badge (green/red muted) + PR badge. Diff data: extend the 5 s poll (`Grove.swift:168`) to batch `git status --porcelain` + `git diff --numstat` per *visible* worktree in one detached task; store on `Worktree` (`dirty`, `additions`, `deletions`). Keep `pin.fill`, selection background, context menus.
- **Acceptance:** visible rows show status + branch + diff summary; poll cost bounded to visible roots.

### 4.3 Triage ordering + compact density
- **Files:** `Sources/Grove/Workspace.swift:134-139` (`visibleTrees`), `Sources/Grove/Grove.swift` (row metrics), `Sources/Grove/Settings.swift` (toggles).
- **Change:** sort = pinned first → status precedence → alphabetical, behind `@AppStorage("triageSort")` (default on). `@AppStorage("compactSidebar")`: 11 pt font, 4 pt padding, single-line rows (status + branch + diff inline).
- **Acceptance:** failed/awaiting worktrees sort to top; compact mode fits 30 worktrees in a 13"/14" viewport without scrolling.

### 4.4 PR badge
- **Files:** `Sources/Grove/Workspace.swift:171` (existing fetch), sidebar rows.
- **Change:** parse `state`, `mergeable`, `statusCheckRollup` from the existing JSON into a small `PRBadge` view (`#num` + distinct symbol per state); render only on rows with an open PR; keep raw JSON display in Settings.
- **Acceptance:** rows with PRs show number + check-state symbol; no row relies on color alone.

### 4.5 `awaitingInput` detection (explicit protocol, deferred)
- **Constraint:** per `docs/ARCHITECTURE.md:83`, do NOT infer from output silence. Requires an agent-presence protocol (e.g. OSC 3008/5379 consumption or wrapper exit-code contract in `PersistentTerminal.wrapper`). This plan stages the enum/sort/UX; detection lands as a follow-up behind the protocol decision. Documented as a known limitation.

## 5. Phase 5 — Lifecycle polish

### 5.1 Non-blocking create with immediate tab + streamed setup
- **Files:** `Sources/Grove/Workspace.swift:175-187`, `Grove.swift` (sheet), `Settings.swift:83` (palette gate).
- **Change:** on create, immediately open a tab named for the branch and stream the git worktree-add / fetch output into that pane's PTY (reuse the script-tab mechanism, `Session.swift:29-36`); sheet gets `ProgressView` + Cancel (cancels the detached task); palette "Create worktree" disabled while `busy`.
- **Acceptance:** tab visible while git runs; output streams live; Cancel aborts; double-invoke impossible.

### 5.2 Post-create setup hooks
- **Files:** `Sources/Grove/ScriptPreset.swift`, `Settings.swift`, `Workspace.swift`.
- **Change:** optional per-repo setup script (npm install / .env copy / direnv allow) auto-runs in the new worktree's pane right after creation, streaming live; Stop (⌘.) works mid-run; failure shows banner (§2.2), never blocks UI.
- **Acceptance:** setup visible/cancellable; failed hook doesn't block tab usage.

### 5.3 Risk-displayed destructive dialogs + ⌘Return confirm
- **Files:** `Sources/Grove/Grove.swift:172-174,244-253`, `Workspace.swift:157-166` (existing helper).
- **Change:** before presenting the remove dialog, gather: uncommitted/untracked counts (`git status --porcelain --untracked-files=all`), unpushed commits (`git log @{u}.. --oneline` guarded for missing upstream), active-process panes (`Program active` state); render in the dialog message. Add `.keyboardShortcut(.return, modifiers: .command)` on the destructive button.
- **Acceptance:** dialog shows all three risk lines when present; ⌘Return confirms, Esc cancels.

### 5.4 Reattach toast + wake refresh
- **Files:** `Sources/Grove/Grove.swift` (TransientBanner), `Session.swift`, `Workspace.swift`.
- **Change:** when a *restored* (not freshly created) pane transitions Starting → Shell after relaunch, show a transient "Reattached to N active agent sessions" banner (auto-dismiss ~4 s, non-focus-taking). Observe `NSWorkspace.didWakeNotification` → `model.reload()` for fresh state after sleep.
- **Acceptance:** relaunch with persistent terminals shows the toast with correct count; post-wake git state refreshes within ~1 s.

### 5.5 New Checks
- **Files:** `Checks/`.
- **Change:** (a) removal-session-cleanup check (§1.1); (b) grep-gate Check: no `.repeatForever`/`TimelineView` outside profile-gated code paths; (c) light-theme smoke check where feasible.
- **Acceptance:** `scripts/check.sh` runs green with new checks.

---

## 6. Validation strategy (every phase)

1. `swift build` (or `make` per Makefile) must pass.
2. `scripts/check.sh` — all existing Checks (State/Git/Script/OpenTarget/tmux/relaunch) stay green.
3. Manual smoke per phase acceptance criteria.
4. Phase 3+: profile-toggle smoke in both tiers; a11y preference toggles.

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Focus restoration races with sheet dismissal on macOS 14/15 differences | Implement via `onDismiss` + `DispatchQueue.main.async` re-focus; verify in `Checks/screen_check.py` flow |
| SwiftTerm `nativeBackgroundColor` update mid-session | Re-apply on appearance change; verify no scrollback clearing |
| tmux kill-session during in-flight write | Reuse exact `closeTab` teardown order (proven by `tmux_check.py`) |
| Poll expansion cost (diff/numstat per worktree) | Batch in one detached task, cap to visible roots, keep 5 s cadence |
| Material/animation regressions on older macOS | Feature-gate Material API; Efficient tier remains the fallback |
| State string parsing brittleness | Parse at assignment; add exhaustive unit mapping (§4.1 acceptance) |

## 8. Council review outcome

**Verdicts: APPROVE-WITH-CHANGES from all 4 reviewers** (AppKit/focus, performance/systems, product/UX, adversarial safety). Full verdicts and change requests: `docs/UIUX-PLAN-REVIEWS.md`. Deltas applied to this plan before implementation:

- **§1.1 revised:** sessions ended FIRST (closeTab teardown shape), then `Git.remove`, then unconditional metadata cleanup; partial-failure surfaces as error (ARCHITECTURE.md:89). Removal-cleanup Check is GUI-gated, not headless.
- **§1.2 revised:** cache last-applied terminal background color; assign only on change (updateNSView fires on every state publish; nativeBackgroundColor setter does not clear scrollback).
- **§2.1 revised:** focus snapshot taken *before presenting* sheets/alerts (no first-responder event hook exists in SwiftUI); optional `LocalProcessTerminalView` subclass publishes focus gain/loss for §2.5's border; `lastFocusedPaneID` transient, not persisted.
- **§2.3 revised:** palette arrow-key nav via scoped `NSEvent.addLocalMonitorForEvents(.keyDown)` (onMoveCommand won't fire while the query field is first responder); Escape hierarchy: exit substate → clear query → close.
- **§2.4 revised:** ⌘W closes focused pane, escalates to tab when last pane; copy path uses ⌃⌘C (⇧⌘C collides with terminal paste-selection muscle memory); plain ⌘C never intercepted while terminal has a selection; remove hidden duplicate ⌘N binding; tab cycling follows `saved.tabs[path]` order.
- **§2.5 revised:** accent border driven by published focus state + `window.isKeyWindow` (no body-evaluated predicate).
- **§2.7 added:** ⌘F with no terminal focus → focus selected worktree's first pane, then invoke find.
- **§3.1 revised:** app-level didBecomeActive/didResignActive (not per-window); explicit objectWillChange on tier flips; dwell-based hysteresis (downgrade at `.serious`+ thermal after ≥15 s dwell; upgrade after triggers clear ≥M s); window-not-key affects animations only, never materials; tier change crossfades ~0.15 s even in Efficient.
- **§3.3 revised:** SF Symbols (`bolt.fill`/`leaf.fill`) not emoji; trigger text in popover only; fixed-width pill; metrics computed on popover open.
- **§3.4 revised:** Efficient forces static cursor by overriding `cursorStyleChanged` (DECSCUSR re-enable guard); ligature/FPS-cap claims dropped (no such API in pinned SwiftTerm).
- **§4.1 revised:** exhaustive state mapping incl. `"Ended"` (neutral) and `"Exited signal"` (failed); status derived at runtime, never persisted (no schema migration).
- **§4.2 revised:** diff stats in `@Published var diffStats: [String: DiffSummary]` keyed by path (Worktree is a regenerated value type); shared `refreshing` guard; tier-gated cadence (HP 5 s + numstat only for non-clean trees; Efficient 10–15 s status-only; skip while app inactive; sequential); diff badge rendered only when dirty > 0, muted single accent, dirty dot in compact mode.
- **§4.3 revised:** hysteresis on triage sort (status must persist two consecutive polls); precedence `failed > awaitingInput > completed > running > idle`; auto-compact above ~12 visible rows; PR badge only when non-green.
- **§5.1 revised:** streaming tab created under repo-root key and moved on success; on failure/cancel — remove tab, `git worktree prune`, delete leftover dir, reload.
- **§5.3 revised:** sheet-hosted risk dialog (`.alert` discards SwiftUI keyboard shortcuts); progressive copy — riskless case is one line; unpushed-commit probe via `rev-parse --abbrev-ref --symbolic-full-name @{u}`; ⌘Return confirm works in sheet-hosted dialogs.
- **§5.4/§2.2 revised:** single shared banner strip (toast reuses it, replaces not stacks, gated by ProfiledAnimation); wake refresh via `.onReceive` on ContentView.

**Implementation proceeds under these deltas.**

## 9. Implementation status (delivered)

**Build:** `swift build` → `Build complete!` (Swift 6.2 toolchain, swiftLanguageModes v5, macOS 14 target). **Checks:** GitCheck, StateCheck, ScriptCheck, OpenTargetCheck, release-policy, screen PTY, tmux PTY — all PASS (one transient `Errno 35` fork failure on tmux_check was green on re-run).

### Delivered
- **§1.1** `Workspace.remove`: sessions ended first via `endSession` (kill-session), teardown failure aborts while tree intact; unconditional metadata cleanup after removal (`Workspace.swift`).
- **§1.2/§1.3** Theme-aware terminal background (dark/light via `appearance` + `colorScheme`), applied only when changed (cached `appliedBackground`); tab pill `Color.white.opacity(0.08)` → `Color.primary.opacity(0.08)`; all chrome colors routed through `AppTheme`.
- **§1.4** Launch failures/non-zero exits render red via `WorktreeStatus` (`TerminalPane`).
- **§2.1–2.2** `snapshotFocus()` before every sheet/dialog; `restoreFocus()` on dismissal (`onDismiss` + error-alert `onChange`) with fallback to the active tab's first pane; background git failures → non-modal `NoticeBanner` (`backgroundError`), user-action failures keep the modal alert.
- **§2.3** Palette: ⌘K primary + ⇧⌘P alias, query field focused on appear, arrow-key navigation via scoped `NSEvent` local monitor, Return executes the selected row, right-aligned shortcut hints, busy-gated create.
- **§2.4–2.7** Menu-backed ⌘W (pane→tab escalation with confirmation), ⌘D/⇧⌘D splits, ⇧⌘]/⇧⌘[ tab cycling, ⌃⌘C copy path, ⇧⌘B copy branch, ⌘N promoted to menu (hidden duplicate binding removed), ⌘⌫/⇧⌘⌫ remove/archive, ⌘⇧A jump-to-attention, ⌘F focus-fallback; worktree actions discoverable in the Workspace menu and palette.
- **§2.5** Active-pane indicator: 1-pt accent border driven by event-tracked `focusedPaneID` (`NSWindow.didUpdate`/`didBecomeKey` observers, publish-on-change only — SwiftTerm's first-responder overrides are not `open`, so no subclass hook; corrected from the plan's original approach per build findings).
- **§3.1–3.3** `PerformanceProfileManager` (`PerformanceProfile.swift`): Auto/HighPerformance/Efficient, dwell hysteresis (15 s downgrade at `.serious`+ thermal or Low Power Mode, 10 s upgrade), app-level active/resign gates animations only, SF Symbol pill (`bolt.fill`/`leaf.fill`) with popover (mode selector, triggers, on-open metrics); Settings picker; tier-gated poll cadence (5 s/15 s).
- **§3.2** `AppTheme` (`AppTheme.swift`): materials only in HighPerformance; `accessibilityReduceMotion`/`accessibilityReduceTransparency` force the Efficient treatment; tier crossfade 0.15 s.
- **§4.1–4.4** `WorktreeStatus` exhaustive state mapping (incl. `"Ended"` neutral, `"Exited signal"` → failed); per-worktree rollup + two-poll hysteresis sort (`failed > awaitingInput > completed > running > idle`) behind `triageSort`; two-line triage rows (status symbol, monospace branch, diff badge only when dirty, dirty dot in compact mode); `diffStats: [String: DiffSummary]` keyed by path, sequential tier-gated poll; PR badge rendered only for OPEN + non-mergeable PRs (green-quiet, red-loud); compact sidebar toggle.
- **§5.1 (partial)** Create sheet shows progress while `busy`; palette create busy-gated; `Git.create` failure rollback (`worktree prune` + leftover dir removal).
- **§5.3** Sheet-hosted `RemoveWorktreeDialog` with risk lines (unpushed commits via upstream probe; running-program panes) and ⌘Return confirm / Esc cancel; hard dirty-block copy retained.
- **§5.4** "Reattached to N saved terminal sessions" transient banner (debounced, auto-dismiss, shares the banner strip) + wake refresh via `NSWorkspace.didWakeNotification`.

### Deferred (follow-ups, documented in plan)
- **§3.4** DECSCUSR cursor-blink suppression in Efficient tier (requires `cursorStyleChanged` override; SwiftTerm's blink is app-driven, not a Grove setting).
- **§5.1 (remainder)** Streaming git output into an immediate tab (needs destination-path move semantics; rollback story already implemented).
- **§5.2** Post-create setup hooks.
- **§5.5** New Checks: removal-session-cleanup (GUI-gated) and repeatForever/TimelineView grep-gate.
- **§4.5** `awaitingInput` detection behind the agent-presence protocol decision (slots exist in enum/sort/UI).



