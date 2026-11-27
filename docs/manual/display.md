# Display: presets, HDR, 10-bit, and calibration

Display presets control refresh rate, colour pipeline, and HDR separately from desktop look modes (`kuwai mode`). Source: `hypr/kuwai/display.lua`, `shell/services/Display.qml`, and `Controls → Display`.

## Presets

| Preset | What it changes |
| --- | --- |
| **Everyday** | Each screen runs at the refresh rate configured in `monitors.lua` |
| **Accurate** | Holds Night Shift off, disables direct scanout so colour runs through the shader pipeline, and loads a measured ICC profile if present |
| **Movie** | Sets external screens to 120 Hz for even 24/30/60 fps cadence (fullscreen video uses VRR where supported) |
| **Gaming** | Applies the gaming look mode (no blur, shadows, or animations; tearing allowed) and restores your previous look on exit |
| **Battery** | Drops the built-in panel to its lowest refresh rate (60 Hz) |

Switch presets from `Controls → Display`, the island quick shelf, or the CLI (`kuwai display everyday|accurate|movie|gaming|battery`, `kuwai display list`).

### Automatic switching (`auto_display`)

While on **Everyday** (disable with `kuwai feature auto_display off`):

- An open colour-critical app (Krita, GIMP, Inkscape, Darktable, Kdenlive, Blender, Figma; extend `K.colour_apps` in `user.lua`) switches to **Accurate** until the last one closes.
- A focused, non-fullscreen video player (`mpv`, VLC, Celluloid, Haruna, Clapper) on an external screen switches that screen to **Movie** after a short dwell.
- Running on battery switches to **Battery** unless a colour app or video player is active.
- Picking a preset manually overrides automatic switching until you return to **Everyday**.

## HDR

Leave your monitor's OSD HDR setting on **Auto** so it accepts HDR signals on demand while staying in SDR for normal desktop work. Browsers, terminals, and editors are marked `no_auto_hdr` in `hypr/kuwai/rules.lua` so fullscreen SDR pages do not trigger HDR.

Two ways to watch HDR:

- **In a browser (for example YouTube HDR):** toggle **HDR** in `Controls → Display` or run `kuwai display hdr on|off|toggle`. This switches HDR-capable external monitors (`max_luminance` or `hdr = true` in `~/.config/kuwai/hypr/monitors.lua`) to `cm = "hdredid"` while leaving the built-in panel untouched. Reload the page after toggling so the browser detects `dynamic-range: high`.
- **Automatic HDR (`mpv` and games):** `mpv` (with `target-colorspace-hint-mode=source`) and fullscreen HDR games trigger `render.cm_auto_hdr = 2` automatically under Movie, Gaming, or fullscreen playback. Run `kuwai play [URL]` to send a URL (or clipboard link) directly to `mpv`.

The notch shows an `HDR` indicator when `bin/kuwai-hdr` reads live PQ/HLG output on the wire or when an HDR preset is active.

## 10-bit output

To enable 10-bit colour on a monitor without shifting the desktop out of sRGB, set `bitdepth = 10` together with `cm = "srgb"` in `~/.config/kuwai/hypr/monitors.lua`. If a fullscreen game or video renders black on your GPU/panel combination, switch back to `bitdepth = 8`.

## Calibration

- **By eye:** `kuwai display calibrate [SCREEN]` displays eight full-screen test patterns at native resolution (black level, white level, gamma, gradients, sharpness, uniformity, glow, white point) under **Accurate** and restores your preset when you press `q`.
- **Measured (colorimeter):** `kuwai display profile` prints each monitor's ICC path (`~/.local/share/kuwai/icc/<screen>.icc`) and the ArgyllCMS commands (`dispcal`, `targen`, `dispread`, `colprof`) to generate one. Profiles load automatically when **Accurate** is active.

## Night Shift

Night Shift is manual by default (`Controls → Night Shift` starts `hyprsunset` automatically). Enable scheduled sunset-to-sunrise warmth with `kuwai feature night_light on` (optionally set `K.night` latitude/longitude in `user.lua`). **Accurate** holds Night Shift off automatically.
