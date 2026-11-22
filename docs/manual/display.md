# Display: presets, HDR, 10-bit, calibration

What the screens are for right now, kept separate from the look modes
(`kuwai mode`, which change how windows look). Source: `hypr/kuwai/display.lua`,
the shell's `services/Display.qml`, Controls → Display.

## Presets

| Preset | What it changes |
|---|---|
| **Everyday** | Each screen at the refresh rate `monitors.lua` gives it |
| **Accurate** | Night Shift held off; colour always through the shader pipeline, no direct scanout; a measured ICC profile if the screen has one (below) |
| **Movie** | External screens at 120 Hz (5×24, 4×30, 2×60 fps play evenly in a window or browser; fullscreen video already gets VRR) |
| **Game** | The gaming look mode (no blur, shadows or animation; tearing allowed); leaving gives back the look you had |
| **Battery** | The built-in panel at its lowest rate (60 Hz) |

Switch from Controls → Display (it also shows what each screen is really
running: Hz, bit depth, SDR/HDR, VRR), the notch's quick shelf (the monitor
icon: scroll to change, click for Controls), or `kuwai display NAME`
(`kuwai display list`). A change shows in the notch for a moment.

**Automatic** (feature `auto_display`, only while you're on Everyday): an open
colour app (Krita, GIMP, Inkscape, Darktable, Kdenlive, Blender, Figma…;
`K.colour_apps` in `user.lua` extends it) → Accurate until the last one closes.
A video player (mpv, VLC, Celluloid, Haruna, Clapper) on an external screen,
focused and not fullscreen for a little over a second → Movie, so that screen
is already at 120 Hz before you go fullscreen. Only the screen the player is
on changes rate; a player on the built-in panel changes nothing. Movie stays
until the last such player closes, so looking at the terminal that drives it
(kunai) doesn't switch the rate back and forth: every switch is a modeset,
and a modeset blanks that screen for a moment. The rate is not changed while
that picture is fullscreen. A fullscreen game arms HDR without taking the
Gaming preset. Unplugged → Battery, unless a colour app or a player is in
front. Choosing a preset yourself wins until you return to Everyday.

## HDR

Leave the monitor's own HDR setting on **Auto** (on Acer displays, the OSD
mode label says "HDR" while Auto is selected even during SDR — that only
means it is ready to follow an HDR signal; brightness stays adjustable until
real PQ arrives).

Everyday, accurate and battery keep external screens on the sRGB picture
from `monitors.lua`. Browsers are marked `no_auto_hdr` (`rules.lua`), so a
fullscreen SDR webpage in Chrome/Zen/Firefox never flashes the monitor into
HDR even while Movie or Gaming is active.

Two ways to watch HDR:
- **In Chrome / browser (YouTube HDR):** turn on the **HDR** switch in
  Controls → Display, or run `kuwai display hdr on` (`toggle` / `off`). This
  switches HDR-capable external screens (`max_luminance` or `hdr = true` in
  `monitors.lua`) directly to `cm = "hdredid"` while leaving the built-in
  panel untouched, and is held off automatically while Accurate is active.
  Reload YouTube once after turning HDR on so it sees `dynamic-range: high`.
- **Automatic HDR without toggling (`mpv` / games):** `mpv` (with
  `target-colorspace-hint-mode=source` in `mpv.conf`) and fullscreen games
  tag PQ honestly, so Movie, Gaming, a settled player, or a fullscreen game
  arms `render.cm_auto_hdr = 2` and enters/exits HDR automatically on
  fullscreen. Use `kuwai play [URL]` to send a YouTube link (or clipboard
  URL) straight to `mpv` at 1440p60 AV1 HDR10 with automatic 120 Hz + auto-HDR.

Terminals, editors and browsers are marked `no_auto_hdr`, so a fullscreen
shell or browser tab cannot spuriously trigger `cm_auto_hdr`. The notch
shows a yellow `HDR` label whenever `kuwai-hdr` reads live PQ/HLG on the
wire or an HDR preset is active.

## 10-bit

`bitdepth = 10` with `cm = "srgb"` in `~/.config/hypr/monitors.lua` (the
`cm` keeps the desktop in sRGB; 10-bit would otherwise switch it to wide
primaries). On NVIDIA, XRGB2101010 is refused and Hyprland falls back to
XBGR2101010, which works. If a fullscreen game or video ever goes black, set
`bitdepth = 8` there.

## Calibrating

**By eye:** `kuwai display calibrate [SCREEN]` shows eight full-screen test
patterns at the screen's own size (black level, white level, gamma, gradients,
sharpness, uniformity, glow, white point), each saying what to look for and
what to change in the monitor's menu. → next, ← back, q done. It runs under
Accurate and puts your preset back after.

**Measured:** `kuwai display profile` lists each screen's profile path
(`~/.local/share/kuwai/icc/<screen>.icc`), whether one is there, and the
ArgyllCMS steps for making one with a colorimeter. Accurate applies it; the
other presets don't (an ICC replaces the screen's colour preset, so no
automatic HDR there).

## Night Shift

Manual by default here (the sunset schedule is the `night_light` feature).
Accurate holds it off. Fullscreen video stays neutral either way
(`render.non_shader_cm_interop = 2`).
