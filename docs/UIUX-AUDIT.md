# Grove — UI/UX Friction & Ergonomics Audit

**Historical snapshot:** this audit describes the source before the branch refactor. Its proposals are not current readiness blockers. The original claim that split focus necessarily follows insertion was unsupported; reading `firstResponder` only identifies the split target. The Open control already existed in the terminal toolbar. `Action.key` originally identified rows; shortcut labels require a separate field. See the [corrective branch review](UIUX-BRANCH-REVIEW.md) for verified findings, fixes and remaining limits.

**Scope:** Full audit of `Sources/Grove/` (12 files, ~1,480 LOC) by four parallel specialists: (1) keyboard/focus, (2) information hierarchy/triage, (3) profile-aware visual design, (4) lifecycle/error recovery. Every claim cites `file:line` in the current tree. Classifications: **ANTI-PATTERN** / **GAP** / **OK**. Ad-hoc signing per `AGENTS.md` is accepted policy and is not reported as a defect.

---

## 0. Reality check vs. the target spec

| Spec'd system | Exists? | Evidence |
|---|---|---|
| Command Palette | **Partially** | `Settings.swift` implements a palette menu bound to ⇧⌘P (`Grove.swift:16`); no ⌘K |
| Agent status system (`awaiting_input`/`running`/`completed`/`failed`/`idle`) | **No** | `Session.state` is a stringly-typed `@Published var` (`Session.swift:10`); docs defer agent presence (`docs/ARCHITECTURE.md:83`, `docs/FEATURE-PARITY.md:23-25`) |
| `PerformanceProfileManager` (HighPerformance/Efficient) | **No** | `grep -rniE 'PerformanceProfile|profile' Sources/` → zero hits; no profile `@AppStorage` key |
| Sidebar worktree rows with status/diff/PR metadata | **No** | Rows show only branch icon + name (`Grove.swift:92-101`) |
| Worktree lifecycle with live setup streaming | **Partially** | Creation is non-blocking (`Workspace.swift:175-187`) but tab opens only after git finishes; script tabs stream live (`Session.swift:29-36`); no post-create setup hooks |

The current visual baseline is effectively the "Efficient tier" already — zero materials, zero animations, zero continuous effects (nothing to disable today, but nothing guards against future additions either).

---

## 1. Part 1 — Keyboard-First Ergonomics & Focus Discipline

### (a) Complete shortcut inventory (all declared bindings)

| # | Shortcut | Action | Location | Notes |
|---|----------|--------|----------|-------|
| 1 | ⇧⌘P | Command Palette | `Grove.swift:16` | Not ⌘K |
| 2 | ⌘O | Add Repository… | `Grove.swift:17` | Opens `NSOpenPanel` (`Workspace.swift:64-65`) |
| 3 | ⇧⌘T | New Terminal Tab | `Grove.swift:18` | |
| 4 | ⌘R | Run Primary Script | `Grove.swift:21-22` | |
| 5 | ⌘. | Stop Primary Script | `Grove.swift:23-28` | |
| 6 | ⌘F | Find in Terminal | `Grove.swift:31-34` | **ANTI-PATTERN**: silently no-ops unless terminal already holds focus |
| 7 | ⌃1…⌃9 | Go to worktree 1–9 | `Grove.swift:35-40` | |
| 8 | ⌘N | New worktree | `Grove.swift:119` | **ANTI-PATTERN**: hidden binding — not in any menu, undiscoverable |
| 9 | Return | Create worktree (sheet) | `Grove.swift:180` | |
| 10 | Return | Run first palette result | `Settings.swift:72` | No arrow-key navigation |
| 11 | Esc | Close palette / cancel | `Settings.swift:93`, `Scripts.swift:146` | Ambiguous while query field is first responder |
| 12 | ⌘, | Settings | `Grove.swift:48` | SwiftUI-native |

**Explicitly absent (grep-verified):** ⌘W, ⌘D/⇧⌘D (splits), tab cycling, ⌘⇧A/⌘U (jump to attention), ⌘K, copy-path/branch bindings, menu key-equivalents for worktree actions.

### (b) Focus-management findings

No `makeFirstResponder`, `makeKeyAndOrderFront`, `@FocusState`, `.focusable`, or event monitors exist in Grove's own sources — so the classic focus-steal anti-patterns are absent (the only `firstResponder` read is `Workspace.swift:98`; terminal focus plumbing lives inside SwiftTerm, `MacTerminalView.swift:1054`).

| ID | Class | Finding |
|---|---|---|
| F1 | OK | Split insertion reads real first-responder state (`Workspace.swift:98`) — this identifies the insertion target; focus transfer requires separate verification |
| F3 | **ANTI-PATTERN** | Background 5 s git poll failures route to `model.error` → modal `.alert` (`Grove.swift:184`, `Workspace.swift:146`) — a transient poll failure can capture keystrokes while the user types in a terminal |
| F4 | **ANTI-PATTERN** | Closing the create-worktree sheet / error alerts hands focus back to the window generically — no mechanism restores it to the previously active terminal pane |
| F5 | **GAP** | Palette (`Settings.swift`) does not explicitly focus its query field on presentation; first keystroke can be lost |
| F6 | **ANTI-PATTERN** | ⌘F find sends `performFindPanelAction` unconditionally (`Grove.swift:31-34`); with no terminal first responder it silently no-ops with no feedback |
| F7 | **GAP** | No visual active-pane indicator in split layouts — the focused pane is indistinguishable |

### (c) Command Palette status

Exists (`Settings.swift`) but: no ⌘K alias, no arrow-key navigation, only "Run first result" (Return), no shortcut hints on rows, "Create worktree" not busy-gated (`Settings.swift:83`). Many actions remain mouse-only: archive/pin/rename/remove worktree, open in IDE (existing Open toolbar control), copy path/branch, splits, tab close.

### (d) Prioritized fixes

- **P1:** Deterministic focus restoration — track `lastFocusedPaneID` on pane focus; on sheet/alert dismissal, re-focus that pane's terminal. Reuse the `Workspace.swift:98` predicate.
- **P1:** Gate poll-path errors to a non-modal banner; reserve `.alert` for user-initiated failures (`Workspace.swift:186,195,199,208`).
- **P2:** Palette: explicit query-field focus on appear, arrow-key selection, ⌘K alias, per-row shortcut glyphs (add shortcut metadata separately from the stable action identity).
- **P2:** Active-pane indicator — observe `window?.firstResponder === view` in `TerminalPane`; 1-pt accent border on focus.
- **P2:** Add missing core shortcuts as menu items (⌘W close, ⌘D/⇧⌘D split, tab cycle ⇧⌘]/⇧⌘[, copy path ⇧⌘C, copy branch); promote hidden ⌘N into a `CommandGroup`.
- **P3:** ⌘⇧A "jump to next pane/worktree needing attention" (requires the status enum from Part 2) plus a sidebar attention badge.
- **P3:** ⌘F falls back to `lastFocusedPaneID` before sending `performFindPanelAction`.

## 2. Part 2 — Multi-Agent Information Hierarchy & At-a-Glance Triage

**Headline:** No worktree-level status system exists. The only signal is a stringly-typed `Session.state` (`Session.swift:10`) rendered as a 5×5 pt dot inside the terminal pane header (`Grove.swift:278-287`) — invisible until you open the worktree. Sidebar rows show exactly two things: branch icon + name.

### (a) Status-state mapping (existing → proposed)

| Existing string | Assigned at | Current rendering | Proposed state | Class |
|---|---|---|---|---|
| `"Starting"` | `Session.swift:10` | green dot + text | `running` (provisional) | **GAP** — indistinguishable from healthy running |
| `"Shell"` | `Session.swift:43,62` | green dot, `.secondary` 10 pt | `idle` | **GAP** — rendered identically (same green) as running |
| `"Program active"` | `Session.swift:62` | green dot | `running` | **GAP** — closest signal to "agent streaming"; only visible in open pane header |
| `"Exited"` | `Session.swift:43` | gray dot (`hasPrefix("Exited")`) | `idle` | **GAP** |
| `"Exited \(exitCode)"` | `Session.swift:60` | gray dot + raw string | `failed` (≠0/signal) · `completed` (0) | **GAP** — exit code in string, never parsed |
| `"Launch failed: …"` | `Session.swift:61` | **green dot** (`hasPrefix("Exited")` is false) | `failed` | **ANTI-PATTERN** — hard failure shown as healthy green |
| `"Ended"` | `Session.swift:48` | n/a | `idle` | OK |
| `awaiting_input` | — | — | — | **GAP** — no OSC/prompt protocol; docs explicitly defer inference from silence (`docs/ARCHITECTURE.md:83`) |

Additional GAPs: `Session.muted` (`Session.swift:11`) is never read by any view; PR JSON is fetched (`Workspace.swift:171`) but only rendered as raw text in Settings (`Settings.swift:92`) — never as a row badge.

### (b) Sidebar row anatomy — what exists vs missing

- Exists and worth keeping: persisted pins/archives with pinned-first sort (`Workspace.swift:132-139`), group expansion with search-aware expand (`Grove.swift:80-91`), context menus (`Grove.swift:102-108`), zero animations.
- Missing: status icon per row, uncommitted diff summary (`+42 −12`), CI/PR badge, monospace branch badge, compact/high-density mode (rows are ~2-line-height with 10 pt padding, `Grove.swift:99`), status-first triage ordering.

### (c) Anti-patterns

1. Green dot for launch failures (above).
2. **ANTI-PATTERN** — background poll failures become modal alerts (`Workspace.swift:146,166` → `Grove.swift:184`), hijacking triage flow.
3. **ANTI-PATTERN** — PR metadata dead-ended in raw JSON text.
4. No sorting by attention; alphabetical only within pinned/archived groups.

### (d) Prioritized redesign

- **P1:** Introduce `enum WorktreeStatus { awaitingInput, failed, running, completed, idle }`; parse exit codes out of `Session.state`; compute per-worktree rollup in `Workspace` over `sessions` with precedence `awaiting_input > failed > running > completed > idle`.
- **P1:** Two-line sidebar row: status dot (state-bearing SF Symbol, never color alone) + monospace branch + `+adds −dels` monospaced digit badge; extend the 5 s poll (`Grove.swift:168`) to batch `git status --porcelain` + `git diff --numstat` per visible worktree; keep `pin.fill`.
- **P2:** Status-first sort with pinned override, behind `@AppStorage("triageSort")` default-on (closes `docs/FEATURE-PARITY.md:25`).
- **P2:** Compact density toggle (`@AppStorage("compactSidebar")`): 11 pt font, 4 pt padding, single-line rows → 30 worktrees in one viewport on a 13"/14" display.
- **P2:** `PRBadge` parsed from `state, mergeable, statusCheckRollup` (`Workspace.swift:171`) with distinct symbols per state.
- **P3:** Route poll errors to row-level warning + retry instead of modal alert.
- **P3:** `awaiting_input` detection requires an explicit agent-presence protocol (OSC 3008/5379 or wrapper exit-code contract) — do not infer from silence, per architecture docs.
- **P3:** Wire or delete `Session.muted`.
- Keep: zero-animation status rendering. If a running affordance is wanted, prefer a static `bolt` symbol.

## 3. Part 3 — Profile-Aware Visual Design (HighPerformance vs Efficient)

### (a) Existence check — **GAP**

`PerformanceProfileManager` does not exist. No profile enum, no `@AppStorage` performance key, and zero hits across: `NSVisualEffectView`, `*Material*`, `ultraThin`, `vibrancy`, `repeatForever`, `TimelineView`, `withAnimation`, `.animation(`, `spring`, `withTransaction`, `disablesAnimations`, `blur`, `shader`, `drawingGroup`, `accessibilityReduceMotion`, `reduceTransparency`, `thermalState`, `isLowPowerModeEnabled`, focus notifications. `docs/ARCHITECTURE.md` never mentions visual tiering.

### (b) Current visual inventory

| Item | Location | Cost / Class |
|---|---|---|
| Flat accent color | `Grove.swift:64` | Cheap, OK |
| Sidebar/panel backgrounds via `colorScheme` branching with **hardcoded** RGB values | `Grove.swift:54,122,157` | Cheap, but **ANTI-PATTERN** for a token layer |
| Active-tab pill `Color.white.opacity(0.08)` | `Grove.swift:~213` | **ANTI-PATTERN** — invisible/wrong in light mode |
| Terminal background hardcoded dark NSColor | `Session.swift:20` | **ANTI-PATTERN** — ignores the `appearance` setting; "light" theme still renders a dark terminal surface, contradicting `preferredColorScheme` (`Grove.swift:10`) |
| Animations / materials / spinners | none | Nothing expensive to disable today; nothing gates future additions |

### (c) Settings & status-pill findings

- `SettingsView` (`Settings.swift:9-32`): Appearance picker (Dark/Light/System, `Settings.swift:11`), monospaced font picker + size slider (`:12-17`), persistent-terminals toggle with tmux warning (`:18-22`), base ref, fetch-before-create, GitHub toggle. **No performance toggle, no Auto mode, no material/vibrancy option.**
- Battery/lid/focus/thermal detection: **none**. `NSWorkspace` appears only for Finder-reveal and app-opening (`OpenMenu.swift`).
- No status bar / toolbar pill; no popover infrastructure anywhere.

### (d) Accessibility — **GAP**

`accessibilityReduceMotion` / `accessibilityReduceTransparency` are never read. They should map directly onto the Efficient tier's static/instant treatments.

### (e) Prioritized plan — `AppTheme` + ViewModifier token layer

**P0 (land before any material/animation is introduced, so every visual addition is profile- and a11y-gated at birth):**

```swift
enum PerformanceProfile { case auto, highPerformance, efficient }

@MainActor final class PerformanceProfileManager: ObservableObject {
    static let shared = PerformanceProfileManager()
    @Published var mode: PerformanceProfile = .auto
    @AppStorage("performanceProfile") private var stored = "auto"
    var effectiveTier: PerformanceTier {  // .efficient wins if auto triggers apply
        if mode == .efficient { return .efficient }
        if mode == .highPerformance { return .highPerformance }
        // Auto triggers: lowPowerModeEnabled, thermalState != .nominal,
        // window not key, reduceMotion / reduceTransparency
        return PerformanceTier.current  // NSProcessInfo + NSWorkspace checks
    }
    @Published var activeTriggers: [String] = []   // e.g. "MacBook is on Battery Power"
}

struct AppTheme {
    let sidebarBackground, panelBackground, accent: Color
    let terminalBackground: NSColor
    let material: Material?           // nil → opaque fallback in Efficient
    let animationsEnabled, springAllowed: Bool
    let spinner: SpinnerPolicy        // .progress vs .staticGlyph
    static func resolved(for tier: PerformanceTier, scheme: ColorScheme,
                         reduceMotion: Bool, reduceTransparency: Bool) -> AppTheme { … }
}

struct ThemedSurface: ViewModifier { /* material when theme.material != nil, else opaque */ }
struct ProfiledAnimation: ViewModifier { /* transaction { $0.animation = nil } in Efficient/reduceMotion */ }
struct ProfiledSpinner: View { /* static SF Symbol in Efficient/reduceMotion */ }
```

**P1:** Settings picker "Visual profile: Auto (System-Aware) | High Performance | Efficient"; in-window status pill in the sidebar header (`Grove.swift:~72`) opening a `.popover` with mode selector, active triggers ("Switched to Efficient because MacBook is on Battery Power"), and lightweight metrics.

**P2:** Terminal polish — pass `theme.terminalBackground` into `Session.terminal(...)` (`Session.swift:14-20`); expose cursor style/blink + ligature pass-through to SwiftTerm; Efficient tier forces static cursor; debounce rapid `state` re-publishes (`Session.swift:62`).

## 4. Part 4 — Safe Lifecycle Flows, Error Recovery & Developer Ergonomics

### (a) Lifecycle walkthrough (create → setup → run → archive/delete)

- **OK — creation never blocks the main thread:** `Workspace.create` runs `Git.create` in `Task.detached` (`Workspace.swift:175-187`); `Git.swift:55-70` validates-first (branch regex, `check-ref-format`, base-ref `rev-parse`, sibling `.grove-worktrees/<repo>` dir).
- **GAP — no immediate tab / no progress:** tab opens only after create completes (`Workspace.swift:184-185`); with `fetchBeforeCreate` on a slow remote the user stares at a disabled button with no spinner or cancel. No `ProgressView` exists in the codebase.
- **GAP — no post-create setup hooks:** no `npm install`/`.env`/`direnv` chaining. Script tabs *do* open immediately and stream live (`Session.swift:29-36`, `Scripts.swift:24-35`), but nothing chains a script to worktree creation.
- **GAP — palette bypasses busy-gating:** palette "Create worktree" not disabled on `model.busy` (`Settings.swift:83`) vs sheet (`Grove.swift:181`) — double-tap can enqueue two concurrent `git worktree add` calls.
- **ANTI-PATTERN (minor)** — all lifecycle failures funnel to modal `.alert` (`Grove.swift:184`); not inspectable in context.

### (b) Destructive-action safeguards

- **OK — confirmations exist everywhere:** remove worktree `confirmationDialog` noting uncommitted files block removal and branch is kept (`Grove.swift:172-174`); close-tab alert with honest message (`Grove.swift:244-253`); script removal dialog; `role: .destructive`/`.cancel` buttons; hard dirty-block in `Git.swift:48`.
- **GAP — no risk pre-check display:** dialog doesn't show uncommitted counts, unpushed commits (`git log @{u}..`), or active processes before confirm.
- **GAP — no ⌘Return confirm** on destructive dialogs.

### (c) Crash / sleep / daemon recovery

- **OK — strong persistence:** `WorkspaceState` restores layout with broken-bytes preservation (`StateCheck.swift:49-55`); persistent terminals on private `tmux -L grove` server (`Resources/tmux.conf`); relaunch keeps same shell PID, no command rerun, exactly one tmux session (`Checks/app_relaunch_check.py:29-61`, `Checks/tmux_check.py:71-122`, evidence in `docs/evidence/grove-app-relaunch.json`).
- **GAP — no reattach toast:** reattach is silent; no "Reattached to N active agent sessions" affordance.
- **GAP — no wake refresh:** no `NSWorkspace.didWakeNotification` observation; state can be stale up to 5 s after sleep.
- **P0 BUG — orphaned tmux sessions:** `Workspace.remove` calls `sessions[pane.id]?.detach()` (`Workspace.swift:192`) instead of `endSession` (`Workspace.swift:240-247`, which does `kill-session`) — removing a worktree leaves live tmux sessions pointing at deleted directories. `closeTab` does it correctly.

### (d) Theme harmony

- **P0 — terminal background ignores appearance** (`Session.swift:20`, detailed in Part 3b).
- **P0 — light-mode seams:** hardcoded `Color.white.opacity(0.08)` tab pill (`Grove.swift:~213`); hardcoded sidebar RGB values (`Grove.swift:54,122,157`) vs `windowBackgroundColor` divergence.

### (e) Existing test guarantees (Checks/)

`StateCheck.swift` (persist/restore incl. corrupt-file recovery), `GitCheck.swift:8-41` (create/list/rename in paths with spaces, invalid/duplicate branches rejected, dirty removal blocked, ignored files block removal), `ScriptCheck.swift:36-60` (real zsh quoting, no command replay after relaunch), `tmux_check.py:71-122` (no screen leak, passthrough, same-PID reattach, per-pane env, exact cleanup), `app_relaunch_check.py:29-61` (packaged relaunch). **Missing:** no test covering `Workspace.remove` session cleanup (the P0 tmux-leak path); no light-theme rendering check.

### (f) Prioritized fixes

1. **P0** — Kill tmux sessions on worktree removal: replace `detach()` with `try await endSession(pane.id)` (`Workspace.swift:192`).
2. **P0** — Theme-aware terminal background (`Session.swift:20`) + fix light-mode pill/seams (`Grove.swift:213,54,122,157`).
3. **P1** — Show risk inside remove dialog: uncommitted counts (helper exists, `Workspace.swift:157-166`), unpushed commits, active processes; add ⌘Return confirm.
4. **P1** — Create ergonomics: open tab immediately, stream git output into it (reuse script-tab PTY), `ProgressView` + cancel in sheet, busy-gate palette create (`Settings.swift:83`).
5. **P2** — Reattach toast on restored panes; observe wake notification → `model.reload()`.
6. **P3** — Add a Check asserting no tmux session survives `Workspace.remove`.

---

## 5. Implementation roadmap (sequenced)

| Phase | Items |
|---|---|
| **Phase 1 — P0 correctness** | tmux leak fix (4f.1); theme-aware terminal bg + light-mode seams (4f.2); launch-failure dot color (2d) |
| **Phase 2 — Focus & keyboard** | deterministic focus restoration, non-modal poll errors, palette focus + arrow-key nav + ⌘K, ⌘F fallback, active-pane indicator, new core shortcut menu items |
| **Phase 3 — Token layer** | `PerformanceProfileManager` + `AppTheme` + `ThemedSurface`/`ProfiledAnimation`/`ProfiledSpinner`, Settings profile picker, status pill + popover, a11y preference mapping |
| **Phase 4 — Triage** | `WorktreeStatus` enum + rollup, redesigned two-line rows, diff summary poll, status-first sort, compact mode, PR badge |
| **Phase 5 — Lifecycle polish** | immediate tab + streamed setup, risk-displayed destructive dialogs with ⌘Return, reattach toast, wake refresh, palette busy-gating, new Checks for tmux cleanup + light theme |
