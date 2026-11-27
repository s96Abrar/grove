# /brag plan — Grove

## Rubric
- **What is it:** A native macOS coding workspace where every task gets its own Git worktree, with embedded terminals, tabs and splits.
- **Who / what for:** Developers running several coding agents (or tasks) on one repo at once. Grove gives each its own branch and terminal, and tells you which one is waiting on you.
- **What sets it apart:** Native SwiftUI/AppKit (8.6 MB app, no web runtime), no telemetry/account/activation, MIT. tmux-backed sessions survive Quit. "Awaiting input" detection (orange ?) with ⌘⇧A jump.
- **Most impressive claim:** It spots the agent that's stuck on "Do you want to proceed?" and jumps you straight to it.
- **Visual hook:** A wall of agent terminals. One of them is quietly waiting for a "y".
- **Real UI to show:** Sidebar (leaf + "grove" wordmark, LOCAL tag, "A little space for big ideas.", REPOSITORIES, worktree rows with status symbols, +/− diff counts, PR badge), branch header, terminal tabs, awaiting-input state. Empty-state copy "Room to branch out."
- **Tone:** `polished` with a dry `default` hook. Calm dark green, the app's own palette.
- **Share caption:** see share-copy.txt.

## Visual identity (from Sources/Grove/AppTheme.swift + app icon)
- main bg rgb(0.055,0.065,0.06) → #0e1110 · sidebar/panel #161816 · accent rgb(0.68,0.88,0.51) → #ade182
- status: awaiting orange, failed red, completed green, running accent bolt, idle secondary
- Icon: Resources/AppIcon.png (leaf sprout over `> _`)
- Type: SF Pro / SF Mono in-app → Inter / JetBrains Mono stand-ins (no SF on the render machine); "grove" wordmark rounded semibold
- Data: worktrees/branches are fictional placeholders (feature/login-flow etc.); no real paths or user data.

## Music
120 BPM, A minor (Am – F – C – G), beat = 0.5 s = 15 frames, bar = 2 s. Synthesized: soft kick, closed hat, sub bass, warm pad, pluck arp. Cut SFX = soft filtered whoosh + pluck in key, sitting under the music. All cuts on beats.

## Storyboard (21.0 s, 630 frames @30fps, 1920×1080)
| # | Time | Scene | On screen | Motion |
|---|---|---|---|---|
| 1 Hook | 0.0–4.0 | Agent wall | 6 terminal panes pop in on beats, each with an agent scrolling. Pane 5 shows `Do you want to proceed? (y/n)` with blinking cursor. Caption: **"Six agents. One repo. Which one is waiting on you?"** | panes pop 1/beat, logs scroll; at 2.5s everything dims except pane 5 |
| 2 Reveal | 4.0–7.0 | Icon + wordmark | App icon grows, leaf + `grove` wordmark, real tagline **"A little space for big ideas."** | icon scale-in, wordmark slide |
| 3 Worktrees | 7.0–11.0 | App window | Sidebar fills with worktree rows one per beat; header shows selected branch; caption **"Every task gets its own worktree."** | rows stagger in, selection highlight moves |
| 4 Attention | 11.0–15.0 | Awaiting input | `fix/flaky-ci` flips to orange ?, sorts to top; ⌘⇧A keycaps press; terminal switches to the waiting prompt; `y` typed. Caption **"⌘⇧A jumps to the one waiting on you."** | row reorder, key press, typing |
| 5 Native | 15.0–18.0 | Facts | Three settled stat lines: **8.6 MB native app · No telemetry, no account · Sessions survive Quit** | stagger in per beat |
| 6 Outro | 18.0–21.0 | End card | Icon, **grove**, "Room to branch out.", `macOS 14+ · MIT · github.com/s96Abrar/grove` | soft settle, music resolves |

Durations sum: 4+3+4+4+3+3 = 21 s.
