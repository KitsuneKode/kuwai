# kuwai

The rice's name. One desktop, made by one hand: Hyprland underneath (Lua,
`hypr/`), a Quickshell shell on top (`shell/`), one design language across
both (`docs/DESIGN.md`).

## Pillars

1. **Calm glass.** Apple's material and motion, not its chrome: liquid glass
   over real windows, continuous (squircle) corners, one ease-out, springs that
   keep their velocity, nothing that loops.
2. **Fast hands.** Every surface has a key, every key is in the Shortcuts panel
   (Super+/), every action is one keypress away from the next. No process per
   keypress where Lua or a global shortcut can do it.
3. **Never broken.** A bad module is a notification, not a dead session;
   `kuwai doctor` validates with Hyprland itself; upgrades are a checklist.
4. **Honest hardware.** Render on the GPU that owns the busy screen, 10-bit and
   full refresh where the panel has it, VRR only where it helps, no shader
   passes or looping animations burning frames for nothing.

## What it takes, from whom

| From | Taken | Where |
|---|---|---|
| Hyprland 0.57 | Lua config, events, springs, acrylic blur, `cursor_zoom`/`scroll_move` gestures, `window.open_early` | `hypr/kuwai/*` |
| Omarchy | `bind_hold` push-to-talk, sysfs-only GPU probing, launch-or-focus, curve rules | `core.lua`, `gpu.lua`, `actions.lua` |
| HyDE | themes + wallbash, wallpaper daemon, pickers (bridged, not depended on) | `theme.lua`, `hyde.lua` |
| Caelestia / DMS / noctalia / end-4 | pill island, per-monitor surfaces, edge drawers, Material motion tokens | `shell/` (see `docs/BORROWING.md`) |
| Apple HIG, Emil Kowalski, Fluid Functionalism | material, type, motion gates and springs | `docs/DESIGN.md` |

## Toward a release people install

What makes a rice travel (r/unixporn, Hyprland showcase) is a strong first
screenshot, a video, and a one-command install that doesn't break the
person's machine. In order:

1. **Rename through.** Shell identifiers still say `rice` (layers `rice-*`,
   shortcuts `rice:*`, `bin/rice*`, `~/.local/state/rice`). Move them to
   `kuwai` in one pass with aliases for a release, so nothing user-facing
   breaks mid-way.
2. **Island bar by default** (`rice bar island`), Waybar only as the fallback.
3. **Glass mode as the hero shot** (`kuwai mode glass`): acrylic lens blur on
   windows and the shell. Tune it per wallpaper brightness; measure GPU cost on
   the iGPU.
4. **A kuwai theme pipeline** that doesn't need HyDE: wallpaper → palette
   (matugen or wallbash's algorithm) → `kuwai/theme.lua` + `shell/config/Theme.qml`.
5. **Something only kuwai has.** Candidates the 0.57 API makes cheap: a
   Stage-Manager-style layout written with `hl.layout.register`; Mission
   Control (all workspaces, live) in Quickshell; per-app "smart" placement
   learned from where you move windows.
6. **Installer + docs**: `install.sh` that backs up, links `hypr/templates`,
   checks dependencies, runs `kuwai doctor`; README with the screenshot, a
   30-second video and the Shortcuts panel.
