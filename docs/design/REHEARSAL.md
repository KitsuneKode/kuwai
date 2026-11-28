# Rehearsal: every panel, in every state, looked at

`bin/kuwai-rehearse` stages each island panel in each of its states in a
private window, takes a picture, measures what is on it, and puts all of it on
one contact sheet with the faults boxed. It is how a change to the shell is
looked at before anyone sees it on a desktop, and how "it looks fine on my
machine" stops being the test.

```sh
bin/kuwai-rehearse                 # all scenes, text at 100 %, 120 % and 200 % (about a minute)
bin/kuwai-rehearse usage calendar  # only those panels
bin/kuwai-rehearse --scale 1.2     # one text size
bin/kuwai-rehearse --gate          # exit 1 on a new fault (run before a promote)
```

`--pixels 2` draws the pictures at twice the pixels (text at 100 %, nothing
judged): it is how the README's tour (`docs/media/tour/`) is made, from the
scenes `updates/tour`, `system/calm`, `launcher/tour`, `settings/shortcuts-tour`
and `media/playing`. A scene's `late` sets are applied once its panel is up, for
a reading a helper the panel starts would overwrite (`system/calm`); a seed
value `"copy:tests/ui/fixtures/x.png"` copies that repository file into the
private home (the sample cover).

It prints one line per fault and the path of `sheet.png`. **Open the sheet.**
A passing gate means nothing measurable is wrong; whether the frame is good is
still a person's call, and the sheet is where that call is made.

It never touches the session: the shell's files are copied into a bubblewrap
sandbox with its own X server (software rendering), an empty home and no
network or session bus. Helpers are stand-ins that exit at once, so a panel
with no scene data shows what it shows on a machine that has nothing yet.
`/proc/meminfo` there is a calm, fixed one: the machine's own memory never
raises a warning into a frame.

## What a scene is

`tests/ui/scenes.json`. One panel, one state:

```json
{ "id": "usage/stale", "name": "usage", "panel": "UsagePanel",
  "set": [["Limits", "alive", false], ["Limits", "providers", [ … ]]] }
```

- `set` puts services in the state (`[service, property, value]`, or
  `[service, "call", function, [arguments]]`); it is undone after the frame.
- `kind: "worst"` marks data longer than ordinary (a title that is a whole
  sentence, whatever apps a machine has installed). There, shortening with an
  ellipsis is the right answer; everywhere else it is a fault.
- `props` are the panel's own properties; `"@date:2026-11-18T10:10:00"` pins a date.
- `"@now-300s"`, `"@now+5400000ms"`, `"@now-60iso"` are moments relative to the run.
- `seed` (top level) are files written into the private home before start;
  `running` are helpers whose stand-in stays up instead of exiting.
- `screen: true` stages a whole screen instead of the island (the lock:
  `"panel": "../lock/LockView"`, props `{"lock": "@lock", "preview": true}`,
  a wallpaper through `["Hyde", "wallpaper", path]`). Its text is judged on
  the real picture, so a light wallpaper is a real test of the lock's plate.
  `hide` lists item types left out of the frame (the lock's clock digits,
  which clock-ground measures on its own).

A scene is not limited to an island panel. `panel` may name any component as
`../lock/LockView`: a full-screen face takes `size` (`[1920, 1080]`) and, for
the lock and login screens, `props: {"lock": "@lock", "preview": true}` with
`fake` overrides for the stand-in session (`password`, `error`, `checking`,
`name`). `window: true` stages a surface that lives in its own window (the
clipboard shelf, the assistant, the volume and brightness HUD, the toasts): the
sandbox copy of the shell is made mappable without a compositor, the scope is
created, `set` puts services in state (`["Notifs", "at", "items.0.popup", true]`
sets a property of one list entry), `calls` runs a method of the scope once
(`showBrightness`), `after` assigns its properties once it is up (`"@screens"`
is every screen's name, `"@screen"` the first one's, in `calls` too and inside
objects), and the picture is the window's own pixels. A window must have an
`id` on the line after `PanelWindow {` to be found. The dictation ring
(`voxring/*`) is staged this way: `calls` feeds `read` what `hyprctl` would
say (a window, maximised, fullscreen) and `after` sets the voice's `peak`.

A scene may carry `scales` (a list of text sizes) with a `why` when its surface
does not follow Text size yet; today only the clipboard shelf, and a test keeps
it so: fix the surface, then drop the field.

Every `*Panel.qml` under `shell/modules/island/` must have a scene
(`tests/test_rehearse_gate.py`). A new panel gets at least: what a new machine
shows, ordinary data, and the worst data you can think of. A new state of an
old panel (an error, a stale reading, nothing to show) gets a scene too:
states nobody stages are where the slop lives.

## What is judged (`lib/rehearse/gate.py`)

Wrong, whoever looks (red on the sheet, fails the gate):

| Rule | The fault |
|---|---|
| `cut-off` | text runs past the panel, its clip, or the side of its scrolling area |
| `on-top` | one text drawn over another |
| `spills` | text wider than the room it was given, neither wrapping nor shortening |
| `shortened` | ordinary content ends in an ellipsis |
| `small-type` | under 10 px at 100 % |
| `unreadable` | under 3:1 against what is really under it (measured on the picture, over the brightest ground a wallpaper can give the island) |
| `small-target` | a click target under 24 px |
| `too-big` | the panel wants more than the island can give (1080 × 600 on a 1080p screen) |
| `insides` | a helper's name, an exit status, `NaN`, `undefined` shown as words (not text set in the code face: a command to copy or a log is shown as code on purpose) |
| `missing-font` | an icon drawn in a font it didn't ask for (stray letters) |
| `cut-row` | a scrolling list ends on a line of text cut through its middle at full strength (a list with more that way fades its rows out: `components/ScrollFade`) |
| `hidden` | text that should read (its colour stands off its ground) leaves no stroke on the picture: something opaque is drawn over it (ScrollFade's mask once covered the whole Updates list, and white on that black passed as 21:1) |
| `says-nothing` | fewer than three words on the panel |
| `waits-forever` | loading placeholders beside a message that loading failed |

To look at (amber, never fails by itself): `faint` (3:1 to 4.5:1), `empty-band`
(a large stretch of nothing), `many-sizes` (more than six type sizes),
`lopsided` (uneven side insets).

Each rule has a frame it must fault and the same frame put right in
`tests/test_rehearse_gate.py`. A rule that needs an exception gets it from
what the frame says about itself, never from a list of panel names. A surface
that floats over its panel (a `ContextMenu`'s card) says `floats: true`; the
frame records the box it covers, and what lies under it is judged in the
scenes where nothing floats (its own texts and targets are judged as usual).
A light with no words by design (the dictation ring) says `wordless: true`, and
`says-nothing` passes it by.

## Gestures

A whole run also drives the swipe with a real pointer in the same sandbox
(`tests/ui/gestures.qml`; alone: `bin/kuwai-ui-test --case gestures --backend
x11 --motion full --output DIR`). Each rule of a gesture is a check:

- while the pointer is down the row is the pointer: 20 px of pointer is 20 px
  of row, and the fade is the distance travelled;
- let go short and stopped, it comes home; past 40 % of its width, it leaves;
- a flick leaves from anywhere, and a flick back home keeps it even past the line;
- caught on its way home it is taken from where it was, and stays put while held;
- sent away by a button it leaves from rest: no throw without a hand;
- with reduced motion nothing is left half-way.

Every swipe in the shell is `components/SwipeAway` (the notch's list, the
centre, agents, T3, the lock screen's cards), so these checks cover them all.
The checks were proven by breaking the swipe eight ways and watching each one
fail; when you add a check, break the thing it guards and see it fail first.
A new drag is built on `Spring` (interruptible, keeps its velocity), `Fling`
(the pointer's speed over the last 100 ms) and `Theme.swipeDamp` (resistance
past an edge), never on a fixed-length animation.

## The lock clock and the wallpaper

Panels bring their own ground (the island's black), so a wallpaper cannot make
their text unreadable. The lock screen's date and clock have none: they sit on
the wallpaper. `shell/modules/lock/ClockGround.qml` reads how bright the
wallpaper is behind the clock and darkens the top of the screen only as much
as it takes to reach 3.5:1 (nothing over a dark picture). A whole rehearsal
stages it over three painted wallpapers (snow, a bright sky, night) and
measures the clock on the real pictures (`tests/ui/clock-ground.qml`).

```sh
bin/kuwai-rehearse --wall ~/Pictures/walls/*.jpg     # each wallpaper: the clock's contrast, alone and shaded
```

`ok`: readable with little or no shade. `bright`: readable, but the top third
has to be darkened by over a third; fine for a personal wallpaper, a poor
choice for a default. `WRONG`: under 3:1 even shaded. `lib/rehearse/wall.py`
is the same rule as the component, for tools that judge wallpapers
(`wall.lock_clock(path)`).

## The clock face on the three screens

The lock, the login and the screensaver draw their date, digits and glance
lines with one component (`shell/components/ClockFace.qml`, its lines made of
`ClockChip`), each at its own scale (the saver's is `Theme.saverClockScale`).
The lock and login scenes stage it at 100, 120 and 200 % with the rest of the
run: `lock/glance` (weather and Focus on a bright wallpaper) and
`greeter/bright-wall` (the login over the same bright picture, 1920 x 1080: a
screen scene may carry a `size`). Both read their ground from `ClockGround`,
which samples the wallpaper once and takes its zone from the face's own size.

The screensaver is not a scene. `bin/kuwai-ui-test --case saver --backend x11
--text-scale 1|1.2|2 --output DIR` stages `SaverClock` over a painted wallpaper
(`clock-full.png`, `clock-bare.png`, `clock-long.png`) and fails when the face
does not fit the screen.

## The dictation pill

By default the island hosts dictation and the pill stays hidden
(`dictationPill`: `island`); the scenes `dictation/*` stage the real island
(`IslandBar` as a window) in every state of a take, beside music, a meeting
and a waiting notification, and the expanded view (`DictationPanel`).
`bin/kuwai-ui-test --case voxhost` stages
`VoxtypeHost` over a fake voxtype UI and proves a changed pill file is drawn
after the take and never during it.

The pill is shuush's (`osd/kitsune-hud/KitsuneHud.qml`), drawn in this shell
by `VoxtypeHost`; how it shows a take is Settings → Dictation words
(`dictationPill`: `island`, the default; `ticker`; `field`; `words`; `status`), which
`VoxTarget` passes on with the Text size, the target window and the spring
its ring glides on in `$XDG_RUNTIME_DIR/kuwai/voxtype-pill.json`.

```sh
bin/kuwai-rehearse --pill ~/Projects/ai-agents/shussh/osd/kitsune-hud/KitsuneHud.qml --out DIR
```

stages that file (`tests/ui/dictation.qml`, `bin/kuwai-ui-test --case
dictation`) over a painted screen with this shell's own ring and caption, in a
T3-like composer, a terminal, a maximised and a fullscreen window, at seven
moments of a take (quiet, loud, a two-minute take, transcribing, delivered,
cancelled, a mic that sends nothing), text at 1x and 2x. Out come one sheet per
style (`sheet-words.png`, `sheet-ticker.png`, `sheet-status.png`) and
`side-by-side.png` with today's beside them; a cell whose pill lies over the
field says so. `hyprctl` there is a stand-in that answers with the staged
window. Nothing is judged: it is for choosing.

The ticker gets two more sheets (`--ticker` makes only these):
`sheet-ticker-states.png`, at text 1x and 2x, in a composer loud and too
quiet, a window moving mid-take (a frame mid-glide and one settled), a
terminal's long take, a maximised window, transcribing, delivered and
cancelled; and `sheet-ticker-seats.png`, where it sits inside a maximised or
fullscreen window (the centre of the bottom edge, the bottom-left or the
bottom-right corner) over T3 and a maximised terminal. A cell whose pill lies
over the composer or the terminal's prompt says so.

## The known list

`tests/ui/rehearsal-known.txt` holds faults that exist and are not fixed yet.
`--gate` fails on a fault that is not listed and also on a listed one that is
gone, so the list only gets shorter. Today it holds only 200 % text (34 entries): at 100 %
and 120 % nothing is excused (a test keeps it so). A length that holds text is
written `Theme.sp(n)`, which grows with Text size; a bare number there is what
most of that list is made of.

## Looking: the last pass

After the gate, read the sheet as the person who sends back the one wrong
thing. From the references this shell is measured against (Clove, Panacea,
pocket-dots) and from what the first rehearsal found:

1. **What does the eye land on first, and is it the answer?** A panel answers
   one question (how much is left, what needs me, what is playing). The answer
   is the largest or brightest thing; everything else is quieter than it.
2. **One accent per frame.** Colour says state (amber: act soon, red: stopped,
   green: done). Two colours shouting is none.
3. **Empty is a state, not an absence.** It says what is missing and what to
   do, in the panel's own voice, in the place the content would be.
4. **An error sits on the thing that failed**, with its way out beside it, and
   never beside a placeholder that still promises content.
5. **Nothing the program calls itself.** No helper names, exit codes, paths.
6. **Said once.** A fact (how old the reading is, which account) appears in one
   place per frame.
7. **Rows share edges.** Figures line up in columns with tabular numerals;
   insets are the same on both sides; a row's height comes from its text.
8. **It holds at 120 %.** Larger text is a setting people use, not a test mode.
