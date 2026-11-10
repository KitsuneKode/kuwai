---
name: kuwai-ui
description: Build, polish or review any kuwai shell surface in QML (the island, panels, toasts, lock and login screens, the assistant) the way the rest of the shell is built. Emil Kowalski's aiforui.dev rules (design engineering, animate, choreograph, gestures, make-interfaces-feel-better, better-typography, animation-performance) translated from CSS/React to Quickshell, plus the rendering, privacy and cost rules this repo learned the hard way. Use before writing or changing anything under shell/, when something "feels off", stutters, overlaps, or costs CPU at rest.
---

# kuwai UI (QML)

The web skills this distils (`emil-design-eng`, `animate`, `choreograph`, `apple-design`, `gestures`,
`make-interfaces-feel-better`, `better-typography`, `animation-performance`, `break-ui`) speak CSS and
React. Their rules hold; their syntax doesn't. This is the QML side. The design system itself is
`docs/DESIGN.md` (material, type, colour, motion, primitives) and `shell/config/Theme.qml` (every
token). Read DESIGN.md's section for the surface you touch first. Never introduce a value Theme
already names: `bin/rice-tokens` ratchets raw sizes, durations and hex down, and promote fails on a
rise.

## Order of work (aiforui's)

1. **Before building:** name the motion (`animation-vocabulary`), and for anything new with a real
   look to choose, ask the user to run `/prototype` (user-invoked only) or show 2–3 variants first.
2. **Building:** the rules below.
3. **Reviewing:** `break-ui` thinking (longest name, zero items, 12 accounts, two screens, reduced
   motion, text at 120 %), then measure (section 7). `/review-animations` is user-invoked.
4. **Whole app:** `find-animation-opportunities` / `improve-animations` produce plans, not code.

## 1. Motion: tokens, not numbers

| Want | Use |
| --- | --- |
| Arriving, exiting, anything awaited | `Easing.BezierSpline` + `Theme.easeOut` (never ease-in) |
| Moving/morphing on screen | `Theme.easeInOut` |
| A panel from an edge | `Theme.easeDrawer` |
| Durations | `Theme.enterMs` 200 · `exitMs` 150 (exit faster) · `microMs` · `colorMs` · `hoverMs` · `reflowMs` |
| Anything a pointer or a new target can interrupt | `components/Spring.qml` (`Theme.springFast/Moderate/Slow`), not a NumberAnimation |

- A shape the island grows into is a `Spring`; retargeting keeps velocity, so a hover that leaves
  mid-grow turns around without a seam. `NumberAnimation` restarts from its `from`: never on
  anything the user can catch.
- High-frequency interactions (hover, typing, a key held) get no custom motion: instant, or a
  ≤150 ms colour/opacity change. The attention cost repeats every time.
- Motion is never the only signal: a state also changes colour, glyph or words.
- Reduced motion (`Theme.reduceMotion`): Springs settle at once by themselves; anything else that
  moves must check it. Fades stay, travel and bounce go.
- Staggered entrances only for rare, staged reveals (`Theme.revealStepMs` 30–80), never routine
  rows.

## 2. Gestures (gestures skill, in QML)

- **Track phase is the pointer, 1:1.** In `DragHandler.onTranslationChanged`, `spring.snap(v)`;
  no Behavior, no easing on the dragged value. Wrong-way travel is damped (`Theme.swipeDamp`), not
  blocked.
- **Release velocity, not average.** `components/Fling.qml`: `reset()` on press, `add()` per
  move, `vx()/vy()` (px/ms over the last ~100 ms) on release. Dismiss on distance
  (`Theme.swipeThreshold`) OR a flick (`Theme.swipeFlick`); a flick back home keeps it.
- **Release is a spring seeded with that speed** (`s.velocity = v * 1000; s.target = …`).
- **Catchable:** on press, read the spring's current value as the grab origin and `snap` it there.
- **Linked values:** fades and dims derive from the position (`swipeFade` from distance), never
  their own animation; they can't drift apart when the gesture reverses.
- **Dismiss along the axis it entered.** Toasts: right or up. The island peek: up.
- Patterns: `modules/notifications/NotifCard.qml`, `modules/island/NotifPeek.qml`.

## 3. Surfaces and layout

- **Concentric radius:** outer = inner + padding. A 12 px button in a 6 px-padded card wants an
  18 px card.
- **Nothing overlaps by accident.** A centred row next to fixed side columns must reserve their
  width: compute what it needs and grow the container (IslandHover's `needW`/`sideW`), or show what
  fits plus "+N". A fixed width beside variable content is the bug that ran the agent rings under
  the workspaces.
- **Hit areas** ≥ 40×40 in the dense island (a `HoverHandler { margin: 6 }` around a 6 px dot);
  never let two overlap.
- **Shadows for depth, borders for structure.** `Theme.cardEdge` is a structure line, not elevation.
- **Images get an edge:** `ImageEdge` (1 px, white at 0.1 on dark), never a tinted neutral.
- **Optical alignment:** a glyph in a box twice its width (the font's pause) reads as padding; draw
  it (IslandRest's pause mark) or offset it.
- **Padding is a token or a reason.** Space that isn't one of the scale's steps, or that remains
  after its content left (an empty row still laid out, a fixed height around shorter text), is a
  finding.

## 4. Type (better-typography, in QML)

- Always `Label` (components/Label.qml), never a bare `Text`: it picks SF Pro Text/Display by
  size, Apple's tracking, `Theme.textScale` (Settings → Text size) and native rendering.
- **Numbers that change** carry `font.features: ({ "tnum": 1 })`; animated digits use
  `TextMorph`/`RollingNumber`. Clocks, %, countdowns, counts.
- Weight carries hierarchy, a few sizes only: title `wSemibold`, value `wSemibold` rounded, meta
  `textSecondary`/`textTertiary`. Never below 11 px, never weight under 400 below 18 px.
- **Truncate with a way back:** `elide: Text.ElideRight` (middle for paths/files) plus a `Tip`
  with the full string. Cap the width (`Math.min(implicitWidth, N)`) so a long name can't push
  neighbours.
- Typographic characters in strings: `…` `·` `–` `→` and curly quotes, never `...` or `--`.

## 5. Colour and state

- One meaning per colour (DESIGN.md "Colour and severity"): the accent is "where you are" only;
  green done/ok, orange needs-you/near, red out/error/critical, yellow HDR/caffeine.
- Privacy dots follow Apple: **orange = microphone, green = camera** (IslandRest), with who holds
  it in the tip.
- Art-derived colour (Media.artColor) needs a local file: `ColorQuantizer` doesn't read `https://`
  (Media fetches remote art into `~/.cache/rice/art`).

## 6. States every surface has

Loading (the surface's own shape, a `Shimmer` at `Theme.shimmerMs`), empty (one sentence, what to
do), stale (say the age: "as of 21:52"), unavailable ("not connected", once, not rows of dashes),
error (what happened, what to try). Each is designed, not an afterthought. Check them all with the
test hook: `qs ipc -p <shell> call test …` (modules/TestHook.qml) and `bin/rice-fixture`.

## 7. Cost: render only what changes

The shell's budget is 0 % CPU at rest (`bin/rice-check`). What broke it before:

- **A Behavior on a value fed by a high-rate source** (PipeWire peaks, positions) restarts every
  update and redraws every frame: 200/s on the Acer. Sample on a Timer (≤30 Hz) and set the value
  straight (IslandRest's waveform).
- **One tick, not many timers:** five per-bar timers were five unsynchronised redraws. Share a
  tick; `Theme.stepEvery` is the one beat for working rings.
- **Infinite animations** only `running` while visible and needed.
- **Anything per-frame** (`FrameAnimation`, Springs) must settle: a target that depends on the
  value it moves never rests.
- **Peak monitors / watchers** `enabled` only while their surface is on screen.
- **Processes** that stream for the shell's life start with `setpriv --pdeathsig KILL --` (promote
  refuses otherwise). One-shot processes from `createObject` end with `onExited: destroy()`.
- **Poll less:** prefer FileView `watchChanges`, D-Bus signals or event streams over a Timer that
  spawns a process; when you must poll, the interval says why.
- **Measure, don't guess:** `top -H -p <qs pid>` (Wayland+ threads busy = frames), `rice-check`,
  `rice-check --soak` for leaks; compare playing vs paused when media is involved.

## 8. Fullscreen and the notch

The resting notch is under a fullscreen window (Hyprland draws it over the top layer). Only what
`Settings.notifFullscreen` allows (important: critical, warnings, people you can reply to) grows the
notch onto the overlay for that moment; the rest waits in the center with the missed dot. Never
reserve space during fullscreen (the film would reflow).

## 9. Verify before saying done

1. `qmllint --bare` on changed files (promote does it; it misses missing imports: a `Process` needs
   `import Quickshell.Io`).
2. `bin/rice-loadtest HEAD` (fails closed) and, after `rice promote`, `rice-check` "compile: every
   module and component".
3. Look at it: `grim -g "x,y wxh"` of the notch; the hover view needs a real pointer.
4. Say what you could not see.
