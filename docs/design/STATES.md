# kuwai — states, type, motion, and the road to 9.5

Written 2026-11-05. Measured on the live shell, not guessed. Preview of the
target behaviour: `island-states.mp4` (one loop: rest → banner → loading →
error on the row → retry → progress → success → rest), source in
`stageshow-island/`.

## Where we are (measured)

| Fact | Number | Target |
|---|---|---|
| QML files / lines | 161 / 33.9k | — |
| Distinct font sizes | 25 | 9 (the scale below) |
| Literal durations vs tokens | 188 vs 183 | 0 literal outside Theme |
| Raw hex colours outside `config/` | 84 (3 most common now tokens) | 0 |
| `Qt.rgba(...)` literals | 381 | surfaces/inks from Theme |
| Panels with a loading skeleton | 3 (Updates, Agents, Clipboard) | every panel that waits |
| Shell memory after ~8 hot reloads | 488 → 672 MB | ≤ 450 MB, flat |

The reload number is the important one: each Quickshell reload leaves
~25–30 MB behind. Agents editing the live tree reload it dozens of times a
day — that is most of the "memory leak" you feel. The `stable` worktree
exists for exactly this; the live shell must run from it.

## The state system (every surface, same rules)

| State | Shows | Rules |
|---|---|---|
| **Rest** | clock, one count chip per waiting thing | The chip is the memory; banners are said once. |
| **Banner / peek** | what happened + one action | Grows out of the notch. Never more than one action button. |
| **Loading** | skeleton at the content's own geometry | Appears only after 150 ms (no flash), stays ≥ 400 ms once shown, breathes (opacity 1↔0.55, 1.4 s). Never a centred spinner in an empty panel. |
| **Empty** | one quiet line + the next useful action | "Nothing to update · Check now", not a blank card. |
| **Error** | on the thing that failed, in orange, with Retry beside it | Never a modal, never a separate summary card, never a stale failure after a restart (the bug in the screenshot). Words say what failed and what to do. |
| **Progress** | in the notch (ring + step) | The panel folds into the notch; work continues without holding a panel open. |
| **Success** | said once (≤ 1.7 s), green check, then gone | No "Unlocked" + "Welcome back" twice: one moment per event. |

## Type scale (`Theme.t*`)

10 caption · 11 footnote · 12 sub · 13 body · 14 callout · 15 headline ·
18 title3 · 20 title2 · 24 title1 (displays scale from the screen). Hierarchy
comes from colour (Primary .96 / Secondary .72 / Tertiary .50) and one
weight step (Medium → Semibold) **before** size. Numbers that change use
tabular figures. Migrating files onto the tokens is per-module work, not a
blind replace (`size:` also means icon size).

## Motion

- **Open:** shape springs (surfaceIn, ~3% overshoot when growing); content
  fades/unblurs in 160 ms late, once the shape is mostly there.
- **Close:** content out first (90 ms), shape follows 110 ms later,
  critically damped. Closing is faster than opening.
- **Keyboard-driven and repeated actions:** no entrance animation.
- **State swaps inside a control:** every state stays mounted in one cell and
  crossfades (no pop-in, no width jump).
- **Overshoot** only after a flick or for a moment you plugged in.
  The lock stack's arrival no longer overshoots (2026-11-08); OutBack remains
  only on the lock's swipe snap-back (a flick) and its padlock shackle.
- **Reduce motion:** fades only.

## Quickshell practices (from bugs we actually hit)

1. **Never hot-reload the live session.** Develop in the dev tree with a
   second `qs -p` instance or after `kuwai promote`; reloads leak.
2. **`HyprlandFocusGrab.windows` must name the popup window by id.** `parent`
   inside a `PopupWindow` is not the window — that broke the bell's quick list
   (first click inside counted as "outside").
3. **Lazy everything:** `LazyLoader`/`Loader { active: shown || closing }`;
   unload panels ~10 s after close.
4. **No function calls in hot bindings** that rebuild arrays on every model
   change (the bell list ran 4× per notification while closed).
5. **Stop media before teardown** (`Component.onDestruction: stop()`), decode
   video on one screen only, `sourceSize` on every Image.
6. **Validate anything spliced into a Hyprland Lua dispatch** (addresses:
   `^0x[0-9a-f]+$`); use the real API (`hl.dsp.focus`, not
   `hl.dsp.window.focus`, which silently failed and broke paste-back).
7. **Restart-safe services:** a result is shown only if this session saw it
   finish (`Updates.ownedRun`); a dead job is cleared, not reported.
8. One `services/Run` for processes; one Popover component for every popup.

## Road to 9.5 (in order; each is a finishable step)

1. **Reliability (6.5 → 9):** live shell from `stable`; commit; `rice-check`
   gates promote; a reload-leak test (10 reloads, Δ < 20 MB).
2. **Memory (6.5 → 9):** panel unloading; find the reload leak (Pointer/
   Process/FileView singletons are the first suspects).
3. **States (→ 9):** apply the table above to Updates, Notifications,
   Clipboard, Wi-Fi/Bluetooth, Launcher; one `StateView` component.
4. **Type & colour (→ 9):** migrate modules onto `Theme.t*` and colour
   tokens, island first; `rice-check` fails on new literals.
5. **Login (6 → 9):** trace the greeter → Hyprland black gap; one handover,
   monitors on together.
6. **Island quick list / popovers (→ 9.5):** one Popover component with the
   grab fix, hold-to-open with a fill, Esc and outside-click close.
7. **Polish pass with the preview as the bar** — every surface should hold up
   frame-by-frame like `island-states.mp4`.
