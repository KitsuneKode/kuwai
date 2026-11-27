# ADR-004: Per-Monitor Workspace Blocks, Layer Namespace Conventions, and Window Rules

## Status
Accepted

## Date
2026-11-21

## Context
Hyprland numbers workspaces in one global integer space, evaluates layer/window
rules top-to-bottom, and dispatches Lua callbacks synchronously on the
compositor event loop. Several real failures shaped how kuwai organises
workspaces, layers, window actions, and input:

- Assigning `default_name = "1"` on every monitor caused Quickshell (which
  tracks workspaces by name) to conflate the external monitor's workspace with
  the laptop's.
- Stranded workspaces from an unplugged monitor or edge-swipe left one screen's
  block sitting on another monitor, breaking Super+N numbering and Mission
  Control.
- Re-focusing the already-active workspace tripped `workspace_back_and_forth`,
  bouncing the user backward on edge steps or pill clicks.
- Layer rule `blur = false` placed after `^kuwai-.*` (`kuwai-glass`) did not
  undo blur on full-screen surfaces (screensaver, live wallpaper, scrim),
  producing a visible blur seam across the vignette and burning GPU on video
  frames.
- `ignore_alpha = 0.3` on the island and toast layers blurred soft shadows and
  fading cards into visible square/pale halos.
- Apps requesting maximise on startup (Chromium/Electron) trapped tiled
  windows in fullscreen mode 1 where they refused moves and resizes.
- Window actions targeting "the active window" after un-maximising or floating
  raced with focus-follows-mouse as the layout reflowed.
- Binding Escape inside `voxtype_suppress` dropped `wtype`'s first typed
  character (`hyprwm/Hyprland#3165`).

## Decision

1. **Per-monitor workspace blocks and hotplug folding (`hypr/kuwai/workspaces.lua`)**:
   - Allocate a persistent block of 10 workspace IDs per physical monitor keyed
     by monitor EDID description (`1–10`, `11–20`, …) so monitors reclaim their
     workspaces regardless of DP/HDMI port reassignment.
   - Omit duplicate `default_name` values; publish `wsbase.<output>` in state so
     the island numbers each monitor 1–10 independently.
   - In `desktops` mode, switch all other screens first (with cursor warp
     disabled) and the focused screen last so focus stays put and all screens
     slide together.
   - Guard all step, pill-click, and cross-screen jumps against re-focusing the
     currently visible workspace so `workspace_back_and_forth` fires only on
     explicit `Super+N`.
   - On monitor disconnect, fold windows into the matching slot on a remaining
     screen and persist origin workspace IDs in state (surviving power flaps and
     reloads); on reconnect, restore them within 250 ms without stealing focus
     unless the user was on that screen.
   - Immediately reclaim stray workspaces: if hidden, move back to owner; if
     visible on the wrong screen, migrate its windows into a free local
     workspace so nothing jumps screens visibly.

2. **Layer namespace convention (`hypr/kuwai/rules.lua`)**:
   - Hyphenated `kuwai-*` surfaces receive compositor glass blur (`blur = true`,
     `xray = false`, `no_anim = true`) with per-surface `ignore_alpha`
     thresholds (`0.3` default, `0.75` for `kuwai-island`/`islandbar`/`osd`/`auth`
     to avoid blurring drop shadows, `0.7` for `kuwai-notifs` to avoid halos on
     fading toasts).
   - Dotted `kuwai.*` surfaces (`kuwai.screensaver`, `kuwai.saver-film`,
     `kuwai.wallpaper`, `kuwai.wallfx`, `kuwai.scrim`) deliberately sit outside
     `^kuwai-.*` so blur is never applied to them.
   - `kuwai-auth` adds `no_screen_share = true` permanently.

3. **Window actions, popups, screen-share privacy, and input (`hypr/kuwai/actions.lua`, `browsers.lua`, `automation.lua`, `rules.lua`, `motion.lua`, `voxtype.lua`, `core.lua`)**:
   - Target all multi-step window actions by window address, never active
     window. In `float_toggle`, float to the target box before exiting
     fullscreen so browsers perform one layout pass instead of two.
   - Detect browser sign-in/wallet popups in-process using `window.open_early`
     (enable `<class>-extra` floating rule when the browser already has a
     window) and `window.title` (size/place known popups or re-tile normal
     `Ctrl+N` windows once loaded, up to 10 s), replacing external socket
     watchers.
   - Engage `no_screen_share` window rules and mute notifications only after a
     capture session runs >2.5 s (distinguishing real screen shares from
     screenshots), honouring `kuwai.capture_hold` + grace period for the shell's
     own live previews and `kuwai.privacy_resync()` across shell restarts.
   - Suppress unsolicited `maximize` events globally; disable shadows on tiled
     windows (`flat-tiles`); apply `opaque` plus `1 override 1 override 1 override`
     in `focus` mode so per-app opacity rules do not make windowed browsers
     translucent (`hypr/kuwai/modes.lua`).
   - Share motion curves with `Theme.qml` (critically damped springs for window
     and workspace slides, no looping border-angle animation to preserve VFR).
   - Determine active screen via `kuwai.where()` (focused monitor if a key was
     pressed in the last 5 s or pointer/focus agree, else pointer's monitor,
     since Hyprland Lua exposes key events but not pointer motion).
   - Defer timer creation until after `config.reloaded` with active monitors
     (`K.after_load`) because timers created during load crash
     `Hyprland --verify-config` on exit in Hyprland 0.57.
   - Keep Escape unbound inside `voxtype_suppress` (`hyprwm/Hyprland#3165`);
     use a single auto-consuming Escape bind outside it to cancel dictation
     without a polling daemon.

## Alternatives Considered

- **Using `blur = false` overrides on `kuwai-screensaver` / `kuwai-wallpaper`**:
  Rejected because Hyprland did not clear the earlier `^kuwai-.*` blur rule.
- **External Python socket daemon (`zen_popups.py`) and systemd Escape watcher**:
  Rejected due to extra processes, `hyprctl` round-trip latency, and races.

## Consequences
- Any new non-blurred overlay layer must use the `kuwai.<name>` (dot) namespace
  convention; any blurred glass layer uses `kuwai-<name>` (hyphen).
- Per-monitor workspace behaviour remains consistent across hotplugs, reloads,
  and Quickshell restarts.
