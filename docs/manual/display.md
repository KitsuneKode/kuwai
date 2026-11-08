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
`K.colour_apps` in `user.lua` extends it) → Accurate until the last one closes;
unplugged → Battery. Choosing a preset yourself wins until the next trigger.
Movie is never automatic: changing the rate as a video goes fullscreen would
blank the screen each time.

## HDR

Leave the monitor's own HDR setting on **Auto**. Hyprland (`render.cm_auto_hdr`)
switches a screen to HDR when HDR video or a game goes fullscreen and back
after; ordinary video stays SDR. The notch says **HDR** when it happens.

mpv must tag its output with the source's colours, not the screen's:
`target-colorspace-hint-mode=source` in `mpv.conf`. Without it (mpv > 0.40's
default, `target`) SDR films were sent as PQ/BT.2020: fullscreen flipped the
screen to HDR (a black flash) and, with the monitor's HDR off, looked washed
out. See `docs/research/2026-11-08-display-presets.md`.

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
