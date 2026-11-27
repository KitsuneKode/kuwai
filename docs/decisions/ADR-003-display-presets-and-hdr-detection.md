# ADR-003: Display Presets, Automatic Colour/HDR Management, and Wire-Level HDR Detection

## Status
Accepted

## Date
2026-11-21

## Context
Colour-critical work, cinema playback, gaming, and battery operation require
conflicting display signal settings (refresh rate, Night Shift, ICC profile,
direct scanout, and HDR modesets):

- Leaving `render.cm_auto_hdr` enabled globally caused external monitors to
  modeset into wide gamut and back (black flash, shifted greens, stalled
  frames) whenever any fullscreen app merely advertised HDR metadata.
- Using `cm_auto_hdr = 1` (BT.2020) on a DisplayHDR 400 panel (~90% P3, ~2/3
  Rec.2020) over-claimed gamut capabilities the panel lacks.
- Switching into `movie` (120 Hz) across every external monitor, or reverting
  2.5 s after focus left a video player to its driving terminal, caused
  repeated 200↔120 Hz blackout modesets (5 round trips in one evening).
- `hyprctl hyprsunset identity` alone left Hyprland's reported temperature at
  the old warm value, causing UI indicators to show Night Shift still active.
- Hyprland's `colorManagementPreset` still reported `"srgb"` when automatic HDR
  sent a PQ infoframe on the wire.

## Decision

1. **Five display presets layered over `monitors.lua` (`hypr/kuwai/display.lua`)**:
   - `everyday` (user's `monitors.lua` rates + sunset Night Shift),
     `accurate` (Night Shift held off, shader-managed colour, no direct scanout,
     optional per-screen ICC profile under `~/.local/share/kuwai-data/icc/<desc>.icc`
     with trailing serial stripped), `movie` (120 Hz for even 24/30/60 fps
     cadence on external screens, panel rate unchanged), `gaming` (pairs with
     the `gaming` look mode), and `battery` (60 Hz built-in panel, externals
     untouched).
   - Wrap `hl.monitor` once via `_G.__kuwai_raw_monitor` (avoiding wrapper
     stacking across reloads) so presets re-issue each screen's own rule with
     only mode/colour overrides while preserving position, scale, VRR, and bit
     depth.
   - Apply presets via config reload so leaving any preset restores the exact
     declared configuration.

2. **Automatic preset precedence (`auto_display`, active only over `everyday`)**:
   - Precedence: colour-critical app (`accurate`, except under fullscreen video
     where reloading sRGB while PQ is active leaves wide primaries stuck) >
     external-screen video player (`movie`, applied only to the monitor hosting
     the player, never modesetting under fullscreen video, and held until the
     last external player closes rather than dropping on focus change) >
     unplugged (`battery`).
   - Arm `cm_auto_hdr = 2` (`hdredid`, using the screen's own EDID primaries)
     only in `movie` / `gaming` or on fullscreen video/games without triggering
     a rate modeset; default `cm_auto_hdr = 0` (`hypr/kuwai/system.lua`).

3. **Night Shift reset sequence (`hypr/kuwai/core.lua`)**:
   - Turn Night Shift off by setting temperature to `6500` before issuing
     `identity` (`hyprctl hyprsunset temperature 6500; hyprctl hyprsunset identity`)
     so both the signal and reported temperature return to neutral.

4. **Direct wire-level HDR detection (`bin/kuwai-hdr`)**:
   - Query connected DRM connectors' `HDR_OUTPUT_METADATA` infoframe and
     `Colorspace` properties directly through `libdrm` (read-only, without DRM
     master) and report `hdr: true` only for PQ or HLG EOTF, giving
     `shell/services/Display.qml` ground truth after fullscreen transitions.

## Alternatives Considered

- **Trusting Hyprland's `colorManagementPreset` for HDR status**:
  Rejected because it reported `"srgb"` during automatic PQ output.
- **Global `cm_auto_hdr = 1` (BT.2020) always on**:
  Rejected due to unwanted modeset blackouts and over-claimed gamut on P3-class
  HDR400 panels.

## Consequences
- Everyday desktop usage incurs zero spurious HDR or refresh-rate blackouts.
- Colour apps automatically disable Night Shift and apply measured ICC profiles
  without manual toggling.
- `bin/kuwai-hdr` depends on Linux DRM `hdr_output_metadata` struct layout via
  `ctypes` and degrades cleanly to `{}` if unreadable.
