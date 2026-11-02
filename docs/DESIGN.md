# Design

The foundation is the glass HUD (first built as `~/.config/quickshell/glass-osd`).
Every new surface should feel like it came from the same hand. Tokens live in
`shell/config/Theme.qml`; use them instead of literals.

## Material: liquid glass

Hyprland does the blur, the surface draws the material (`components/GlassCard.qml`):

- **Tint:** dark, ~46% alpha (`Theme.glassTint`), so the blur reads through.
- **Sheen:** vertical light, bright at the top, clear in the middle, a faint
  refracted band at the bottom.
- **Rim:** a 1px specular edge, brightest top-left, a weaker bounce bottom-right.
- **Hyprland side:** every surface is a layer named `rice-*`, with blur,
  `ignore_alpha 0.3` (blur only under the card, not the clear margins),
  `xray 0` (blur real windows), and `no_anim` (the surface animates itself).
  This is all in `hypr/kuwai/rules.lua` already; just name new layers `rice-<thing>`.

## Type

Apple's own faces, from `/usr/share/fonts/apple-fonts`, all through `components/Label.qml`:

- **SF Pro (variable)** for all UI text. Its `opsz` axis runs 17 (the Text cut) to
  28 (the Display cut); `Theme.opszFor(px)` sets it from the pixel size like
  macOS does, so captions get Text's open spacing and titles Display's tighter one.
  Weights are Apple's: 400 / 510 / 590 / 700.
- **Tracking is Apple's**, read from the fonts' `trak` tables (`Theme.tracking(px, rounded)`):
  e.g. 11px +0.06, 13px −0.08, 14px −0.15, 15px −0.23, 20px −0.45, 28px +0.38.
  macOS applies it automatically; Qt doesn't, so we do.
- **SF Pro Rounded** for numerals (`Label { rounded: true }`): count badges, the
  HUD's level and battery. Apple's widget / Control Center habit.
- Not used: SF Compact (watchOS), New York (serif).
- No uppercase or letter-spaced labels; hierarchy from size and weight.
  Changing numbers use tabular figures and a fixed width.
- Over glass, text is brighter than on a solid surface: .96 / .72 / .50.
- The voxtype HUD style (`~/.config/voxtype/osd/kitsune-hud`) follows the same
  rule: variable SF Pro pinned to the Text cut with Apple's tracking.

## Colour and severity

Apple's dark-mode system colours: `Theme.red #ff453a · orange #ff9f0a ·
yellow #ffd60a · green #30d158 · blue #0a84ff`.

Severity changes the material, not just one word's colour:

| Level | From | Look | Behaviour |
|---|---|---|---|
| critical | D-Bus urgency Critical | red wash + edge, `CRITICAL` chip, icon badge, one glow ring on arrival, first action filled red | sound, stays until dismissed, top of the stack, breaks through DND |
| warning | adapter, or wording ("failed", "battery low", …) | orange wash + edge, `WARNING` chip, icon badge | 9 s |
| normal | default | thick glass (`glassTintThick`) | 5.5 s |
| low | urgency Low | lighter glass, one body line | 3.5 s |

## Motion

Three sources, one rule set: Apple's fluid-interface talks, Fluid
Functionalism (springs), Emil Kowalski (curves, gates).

**Gate first.** Motion only where it has a job: showing where something
came from (the center sliding in from the edge it lives on), state changes,
feedback. Things you hit tens of times a day stay near-imperceptible (rows:
press 0.985, the HUD: 180ms, 6px).

**Springs** (`components/Spring.qml`, interruptible, keeps velocity on retarget):
`Theme.springFast` 0.08s (highlights, fades), `springModerate` 0.16s
critically damped (tabs, things that must land exactly), `springSlow` 0.24s
bounce 0.12 (large surfaces, morphs). Exits are tweens one tier quicker.

**Curves** (`Theme.easeOut` 0.23,1,0.32,1 · `easeInOut` 0.77,0,0.175,1 ·
`easeDrawer` 0.32,0.72,0,1). Never ease-in on UI. UI stays under 300ms:
press 140, enter 200, exit 150, glide 150, reflow 200, HUD 180/150.

**The center is a menu, not a tile**: a floating 420px card hanging from
the bar's right corner (where the bell is), ~3/4 of the screen tall, on
`glassTintElevated` (lighter than a window) with a deep shadow, while
Hyprland's `dim_around` layer rule recedes everything behind it. It scales up
from its top-right corner on the moderate spring (0.96 → 1, 6px drop, fade),
content 40ms a step behind, and closes the same way in 120ms. With toasts on
screen it morphs out of the front one instead (slow spring; rectangle and
radius grow into the card, content revealed by the clip). Motion starts only
once Hyprland has mapped the surface.

**Text renders with FreeType** (`renderType: Text.NativeRendering` in Label):
Qt's distance-field atlas drew some labels blank or overlapped with a
variable font at many weight/size combinations.

**Fluid hover** (`components/FluidHighlight.qml`): one highlight per list
gliding on the fast spring; fades in fresh where the pointer lands; doubles
as the keyboard ring.

**Press feedback**: scale 0.97 (rows 0.985), 140ms ease-out, on pointer-down.

**Reduced motion**: `RICE_REDUCE_MOTION=1`, or automatically when Hyprland's
animations are off. Fades and colour stay; travel, scale, glides and the
morph go.

**Performance**: transform/opacity where possible; the glass rim (a CPU
Canvas) shows a plain edge while its size is moving and repaints once at
rest; surfaces exist only while visible (nothing invisible sits over the screen).

Rules kept from before:
- Animate from the current value, so a retrigger mid-exit turns around instead of restarting.
- Leave the way you came: the HUD drops from the bar and goes back up, toasts
  enter from the bar and leave the same way.
- Updates in place get a small pulse (scale 1.02), not a new entrance.
- At a boundary, rubber-band (the brightness track stretches 3.5%).
- Arrivals that matter get one cue, never a loop.

## Toast stack (Sonner)

Ported from Sonner's source (`refs/emilkowalski_sonner/src`), tokens in Theme:
3 visible, 14px gap, each one behind 5% smaller and cut to the front one's
height with its content hidden; hover fans them out to full height and pauses
every timer (they resume, not restart). 400ms CSS `ease` on y/scale/opacity/
height, starting from the current value. Enter drops from one card-height
above; the front exits back up, a fanned-out one exits up from its slot, a
collapsed one behind sinks 40% (500ms, opacity 200ms); unmount after 200ms.
Swipe locks its axis on the first pixel, follows 1:1 away from the corner
(right/up), damps the other way by `1/(1.5+|d|/20)`, dismisses past 45px or
0.11px/ms averaged over the gesture, with a 200ms ease-out throw.

## Notification center

Glass panel from the right edge, grouped by app; each group folds into a
stack (newest on top, two plates peeking out below). Opening focuses search.
Words must all match (app, title, body, status) and matches highlight in
yellow. Filters: All / Unread / Important. Keyboard: ↑↓ select (blue ring),
↵ open, ⌦ or ⌫-on-empty dismiss, →← expand/fold, ⇥ filter, Esc clears then
closes. Searching snaps results instantly (no choreography between keys).
Closing marks everything seen: blue dots and the bell's count clear.

## Interaction

- Feedback surfaces (HUD) are click-through.
- Toasts: click acts (default action, then focus the app's window), right
  click, the hover close button or a swipe right dismisses.
- Every surface gets an IPC entry (`bin/rice …`) so it can be bound to keys.
