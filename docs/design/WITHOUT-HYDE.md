# kuwai without HyDE

kuwai grew on top of HyDE (another Hyprland dotfiles project, installed on the
author's machine). A stranger who installs kuwai without HyDE must get a
working desktop, with HyDE as an optional source of themes. This page is the
state of that on 2026-11-18: every place kuwai touches HyDE, what each does
when HyDE is absent, and the plan for kuwai's own wallpaper and palette.

**Caveat:** at the time of writing another session was reworking the theme and
wallpaper path (uncommitted edits to `bin/kuwai-theme`, `bin/kuwai-wallmap`,
`docs/manual/looks.md`). This page reads those files as they are on
`feat/assistant-agent` and doesn't design around their changes; re-check the
plan below against what that work lands.

## One question, asked in one place

"Is HyDE here?" means **HyDE's scripts are installed:
`~/.local/lib/hyde/globalcontrol.sh` exists.** Whether its `hyde-shell` command
is on PATH is asked separately, only where a script runs it. Each runtime has
one implementation of that test, and nothing else checks by hand:

| Runtime | Where | What it gives |
|---|---|---|
| The shell (QML) | `shell/services/Hyde.qml` | `present`, `hasShell`, `wallpaper` ("" when none), HyDE's folders, `run(args, what)` (runs hyde-shell, or says once what needs HyDE) |
| Hyprland (Lua) | `hypr/kuwai/core.lua` | `K.hyde`, `K.hyde_lib` |
| Scripts (sh) | `lib/hyde.sh` | `hyde_here`, `waybar_start` (HyDE's Waybar, plain waybar, or 1) |
| `bin/kuwai-themes` (Python) | `hyde_here()` | the same file test |
| `install.sh` | sources `lib/hyde.sh` | says which features need HyDE |

`config/Theme.qml` reads HyDE's colour files itself (a config singleton can't
use a service, and this change was not allowed to edit Theme); without them it
keeps its own defaults.

`bin/kuwai-nohyde [--strict] [rev]` starts every singleton of a commit offscreen
with an empty HOME (own D-Bus, no network, own PID namespace, no Hyprland) and
prints what each decided and anything it logged about HyDE;
`tests/test_without_hyde.py` runs it with `--strict`. Services that make a
window (WallFx, Caffeine) can't start offscreen and are left out, and the
panels and lock/login views aren't started; those were judged by reading.

## Inventory

`rg -il hyde shell hypr bin lib greeter install.sh`: 38 files on
`feat/assistant-agent` at 491602c (37 at 5cc9bc0, after the rice → kuwai
rename; `bin/kuwai-hyde-waybar` came with 32ff8dc), plus `shell/services/Hyde.qml`, `lib/hyde.sh`,
`bin/kuwai-nohyde` and `tests/` added here. A widened search (`wall.set`,
`wall.dcol`, `staterc`, `hypr/themes`, `.local/lib/hyde`) found no other
readers. Classes: **(a)** reads a HyDE file for wallpaper, colours or theme;
**(b)** runs a HyDE command or script; **(c)** a comment or a migration note
only. "Before" is what happened without HyDE before this change; "now" is
after.

### (a) Reads a HyDE file: 18

| File | Reads | Before, without HyDE | Now |
|---|---|---|---|
| `shell/config/Theme.qml` | `staterc`, the theme's `theme.dcol` / `kitty.theme`, `wall.dcol` | silent: Theme's own accent (#0a84ff) and background | unchanged (the defined state; verified by the probe) |
| `shell/modules/lock/LockView.qml` | `~/.cache/hyde/wall.set` | black behind the lock, a "Cannot open" warning at each lock | black, no warning (`Hyde.wallpaper`) |
| `shell/modules/screensaver/Screensaver.qml` | `wall.set` (the "still" style) | black, a warning | black, no warning |
| `shell/greeter.qml` | the greeter's copy of `wall.set` (greeter/sync) | black under the welcome, a warning | black, no warning |
| `shell/film.qml` (the clip harness) | `wall.set` | black, a warning | black, no warning |
| `shell/modules/island/ThemePanel.qml` | `wall.set` (the still thumbnail); HyDE's folders in its guides | "No themes found" and a guide pointing at HyDE's folders | says "Themes and wallpapers come from HyDE, which isn't installed", and that live wallpapers and screensavers work without it |
| `shell/services/Glyphs.qml` | `~/.local/share/hyde/{emoji,glyph}.db` | `:` / `;` in the launcher: an empty list | the launcher says the lists aren't there (`Glyphs.emojiMissing`) |
| `bin/kuwai-themes` (also b) | themes, thumbnails, `staterc`, dcols, `wall.set`; runs `theme.switch.sh`, `wallpaper.sh`, `hyde-shell` | `list` **crashed** (traceback; the panel kept its last listing or nothing); `wallpaper` crashed too; `colormode` failed silently | `list`: empty with `"hyde": false`; the three switches exit 3 with the reason |
| `bin/kuwai-theme` | installs a kuwai theme into `~/.config/hyde/themes`; reads `staterc` | writes a theme nothing reads | unchanged (being reworked elsewhere; see the caveat) |
| `bin/kuwai-livewall` | `staterc`, the theme's `wallpapers/live/` | silent: uses `~/Pictures/live-wallpapers` | unchanged |
| `greeter/sync` | copies `wall.set`, `wall.dcol`, `staterc`, the theme's dcol/kitty | silent: skips what's missing (a copy from before HyDE was removed stays) | unchanged |
| `greeter/preview` (a dev tool) | links `~/.cache/hyde`, `~/.config/hyde` into a sandbox | a dangling link, harmless | unchanged |
| `hypr/kuwai/theme.lua` | `~/.config/hypr/themes/theme.conf`, `colors.conf` (HyDE's switcher writes them), `staterc` | silent: nothing applied, theme name "?" | unchanged |
| `hypr/kuwai/look.lua` | the wallbash colours, through theme.lua | silent: the groupbar keeps Hyprland's colours | unchanged |
| `hypr/kuwai/env.lua` | adds HyDE's script folder to PATH when present | skipped | asks `K.hyde` |
| `hypr/kuwai/system.lua` | allows HyDE's `grimblast` path to screencopy | a permission for a path that isn't there, harmless | unchanged |
| `bin/kuwai-hyde-waybar` (run by `kuwai bar`) | edits `[wallbash] skip_template` in `~/.config/hyde/config.toml` | silent: no `~/.config/hyde`, nothing written | unchanged (a HyDE adapter by design) |
| `bin/kuwai` (doctor) | greps HyDE's `env.zsh` for a stale `HYPRLAND_CONFIG` | silent (`grep -qs`) | unchanged |

### (b) Runs a HyDE command: 6

| File | Runs | Before, without HyDE | Now |
|---|---|---|---|
| `hypr/kuwai/hyde.lua` | `wallpaper.sh`, `hyde-config.service`, rofi pickers (Super+Shift+E, A, R, U), `gamelauncher.sh` (Super+Shift+G), `hyde-shell system.monitor` | the whole bridge returns early: not bound, not started | the same, through `K.hyde` (tests/hypr/test_hyde.lua) |
| `shell/modules/island/SystemPanel.qml` | `hyde-shell gamemode` | nothing happened, **and the tile turned on anyway** | kuwai's own gaming mode (`kuwai.mode_toggle('gaming')`, what Super+Alt+G does), which turns animations off, so the tile reads true |
| `shell/services/Updates.qml` | `hyde-shell app system.update.sh up` ("update in a terminal") | nothing | `Hyde.run`: one notification saying it needs HyDE |
| `shell/modules/Shortcuts.qml` | `hyde-shell waybar` (Waybar on/off when the bar is Waybar) | nothing | plain `waybar` |
| `bin/kuwai-ctl` (`kuwai bar`) | `hyde-shell waybar`; masks HyDE's Waybar units | with `bar` = waybar, **no bar at all** | `waybar_start`: HyDE's, else plain waybar; with neither installed, the island becomes the bar and the setting says so |
| `bin/kuwai-shell` | `hyde-shell waybar` when the island didn't load | nothing, and a notification claiming Waybar was up | `waybar_start`; the notification mentions Waybar only if it started |

### (c) Comment or note only: 14

`lib/dispatch.sh`, `bin/kuwai-wall`, `bin/kuwai-shot`, `hypr/init.lua` (load
order; the gate is in hyde.lua), `hypr/kuwai/modes.lua`, `hypr/kuwai/motion.lua`,
`hypr/kuwai/gpu.lua`, `hypr/README.md`, `shell/services/WallFx.qml`,
`shell/services/SystemStats.qml`, `shell/services/Weather.qml`,
`shell/services/Clipboard.qml` (its comment said HyDE's watchers record the
history; kuwai's own `kuwai-clipboard.service` does, so that's corrected),
`shell/modules/notifications/NotifCard.qml`,
`shell/modules/island/LauncherPanel.qml`.

## What a stranger without HyDE gets now

- **Desktop:** Hyprland's background colour, `rgb(0b0b0f)`, with no wallpaper
  (nothing starts a wallpaper daemon: `awww-daemon` is started only by the
  HyDE bridge). Live wallpapers (`kuwai-wall`) work.
- **Lock, login, screensaver "still":** black where the wallpaper would be: a
  shade off the desktop's #0b0b0f. Matching it exactly needs a Theme token
  (`desktopBg`), which this change wasn't allowed to add.
- **Colours:** the island's accent is Theme's blue; Hyprland gets kuwai's base
  material and identity, no theme.
- **Themes panel:** says HyDE isn't installed; the Live and Screensaver tabs work.
- **Launcher `:` / `;`:** says the emoji and glyph lists aren't there.
- **Bar:** Waybar if installed (plain), otherwise the island.
- **Game mode:** kuwai's gaming mode. **HyDE's pickers:** not bound.
  **Update in a terminal:** says it needs HyDE, once.
- `install.sh` lists all of this when HyDE is absent.

Also found while reading (not HyDE): `Settings.weatherLocation` defaulted to the
author's town. Fixed 2026-11-20: unset is the default and means wttr.in's own
guess from the connection (`Weather.automatic`, `Weather.place` names it).

## Plan: kuwai's own wallpaper and palette

The goal: kuwai sets the wallpaper and derives its colours itself; HyDE, when
present, is an adapter that can hand kuwai a picture and a palette. Steps, in
order, each shippable alone:

1. **A wallpaper daemon without HyDE (S, half a day).** Start `awww-daemon` from
   kuwai's own startup (`hypr/kuwai/startup.lua`) when it's
   installed, not only from `hyde.lua`. `awww` (already used by WallFx and HyDE)
   becomes a needed dependency in install.sh. Without a wallpaper set yet:
   nothing shown, the background colour as now.
2. **kuwai's current wallpaper (M, 1 day).** One link,
   `~/.local/state/kuwai/wallpaper`, points at the picture.
   `kuwai-wall set PATH` (bin/kuwai-wall grows a `set`) runs
   `awww img`, moves the link, and asks WallFx for the transition it already
   draws. `Hyde.wallpaper` reads kuwai's link first, HyDE's `wall.set` second;
   the lock, login, screensaver and Themes panel follow with no change of
   their own (they already ask `Hyde.wallpaper`; the property can be renamed
   to a `Wallpaper` service then). greeter/sync copies kuwai's link instead of
   HyDE's.
3. **A palette from the picture (M, 1–2 days).** One colour tool. Recommended:
   ImageMagick (already the optional `magick` dependency, in the official
   repos) in a small `kuwai-palette PATH` that writes
   `~/.cache/kuwai/palette.json` (background, foreground, accent, 6 swatches;
   the same roles as HyDE's `pry1`/`txt1`/`1xa7`) and
   `~/.cache/kuwai/palette.lua` for Hyprland's borders and groupbar. Run by
   `kuwai-wall set`, cached by the picture's hash (as kuwai-themes already
   caches thumbnails). Alternative: Quickshell's `ColorQuantizer` (already used
   for album art) for the island alone, no new process, but then Hyprland and
   apps don't get the palette.
4. **Theme reads kuwai's palette (S, needs Theme.qml).** Theme's colour
   FileViews read `palette.json` first and HyDE's files only when the colour
   mode says HyDE's theme. theme.lua/look.lua read `palette.lua` when HyDE's
   `colors.conf` isn't there. This is the one step that edits Theme.qml.
5. **Wallpapers of kuwai's own (S).** The Themes panel's Wallpapers tab lists
   `~/Pictures/Wallpapers` (configurable) plus the HyDE theme's folder when HyDE
   is present; ↵ runs `kuwai-wall set`. The Themes tab stays HyDE-only and says
   so.
6. **Move what exists (S, a migration).** `migrations/NNNN-wallpaper-from-hyde.sh`
   (piece 2's runner): if HyDE's `wall.set` exists and kuwai's link doesn't,
   point kuwai's link at the same picture and compute its palette once, so an
   existing HyDE user sees no change. Additive: HyDE's files stay.
7. **HyDE as an adapter (S).** With HyDE present, a HyDE theme switch (its
   `wallpaper.sh` writes `wall.set`) also moves kuwai's link: a watch on
   `wall.set` in the Wallpaper service, or a line in `kuwai-themes`. Without
   HyDE, none of this runs.

Files that move: `~/.cache/hyde/wall.set` → `~/.local/state/kuwai/wallpaper`;
`~/.cache/hyde/wall.dcol` → `~/.cache/kuwai/palette.json` (+ `palette.lua`);
HyDE theme `wallpapers/` folders → `~/Pictures/Wallpapers` (HyDE's stay readable).
Total ≈ 5–7 days of work; steps 1–2 alone give a stranger a wallpaper.

Out of scope here, still HyDE's when it's present: GTK and kitty theming
(theme.switch.sh), the rofi pickers, `hyde-config.service`, the
game launcher.
