# kuwai — the Hyprland half of the rice

Hyprland 0.57 configures itself in Lua; hyprlang (`*.conf`) is gone. kuwai is
this rice's Hyprland config: a small set of Lua modules in this repo, plus two
personal files in `~/.config/hypr`. It works without HyDE, and keeps HyDE's
themes, wallpapers and pickers working while HyDE is still installed.

```
~/.config/hypr/hyprland.lua    entry: finds kuwai (KUWAI_ROOT), safety net if it fails
~/.config/hypr/monitors.lua    this machine's screens            (yours)
~/.config/hypr/user.lua        apps, launchers, per-app rules     (yours)

hypr/init.lua                  load order; errors → one notification + `kuwai doctor`
hypr/kuwai/core.lua            K: paths, file probes, binds (K.bind/K.bind_hold/K.submap), state
           gpu.lua             renderer choice (auto/nvidia/intel) + driver env, sysfs only
           env.lua             toolkit/session env, cursor, PATH (idempotent), ssh agent
           system.lua          misc/binds/render/xwayland options, permissions
           input.lua           keyboard, pointer, touchpad, 1:1 gestures
           layout.lua          scrolling tape by default, dwindle/master options
           theme.lua           HyDE theme.conf + wallbash colours → hl.config (no hyq)
           look.lua            base material → wallbash → theme → kuwai identity
           motion.lua          ease-out curves + a critically damped spring
           apps.lua            default terminal/files/editor/browser (user.lua overrides)
           rules.lua           window, layer, workspace rules
           browsers.lua        popups float in place (replaces zen_popups.py)
           actions.lua         float/pin/PiP/zoom/close as Lua (replaces scripts)
           binds.lua           the keyboard (groups = Super+/ panel sections)
           voxtype.lua         dictation: PTT hold, toggle, Esc guard, output submap
           hyde.lua            HyDE bridge (only if HyDE is installed)
           startup.lua         session services, the shell, clipboard, tray
           features.lua        switches for everything automatic (`kuwai feature`)
           workspaces.lua      per-screen workspaces, layout per workspace, console, minimize
           automation.lua      screen-share privacy, battery/game modes, night light, hold-Super
           extras.lua          resize mode, place memory, smart PiP, focus sessions
           modes.lua           focus · default · glass · gaming · battery (applied last)
hypr/templates/hyprland.lua    the entry file, for a fresh machine
bin/kuwai                      CLI: info, doctor, mode, motion, gpu, binds, reload
```

## Everyday

| | |
|---|---|
| `kuwai doctor` | validates the config with Hyprland itself, checks the session, services and scripts |
| `kuwai mode --pick` (Super+Shift+/) | focus / default / glass / gaming / battery; Super+Alt+G toggles gaming |
| `kuwai feature [name on\|off]` | list / switch the automatic things (below) |
| `kuwai binds [word]` | every bind, grouped like the Shortcuts panel (Super+/) |
| `kuwai gpu auto\|nvidia\|intel` | renderer at the next login |
| `kuwai motion full\|reduced\|off` | Hyprland's half of Reduce Motion |
| `hyprctl reload` | re-runs everything from a clean Lua state |

Your changes go in `user.lua` (and `monitors.lua`). Binding keys kuwai already
uses replaces kuwai's bind; `K.apps.terminal = "…"` changes what Super+T opens.
Rules: `kuwai.K.rules.rule({ name = …, match = { class = "^(app)$" }, float = true })`.

## Features (all on by default; `kuwai feature NAME off`)

| Feature | What it does | Keys |
|---|---|---|
| `launch_focus` | app keys focus the open app (again → its next window), launch only if closed | your app keys in user.lua |
| `per_monitor_ws` | every screen owns workspaces 1–10 (the Acer is 11–20 underneath, shown as 1–10); tied to the physical monitor | Super+1…0, Super+Ctrl+←/→ |
| `layouts` | cycle the current workspace: scrolling → dwindle → monocle → floating; remembered | Super+Alt+L |
| `quake` | drop-down console over any workspace, spawned on first use | Super+\`, Super+Shift+\` |
| `minimize` | tuck a window away / bring the last one back | Super+O, Super+Shift+O |
| `screenshare_privacy` | while sharing: DND on, notifications and private apps (password managers, chats) drawn black | — |
| `auto_battery` | unplugged → battery mode, plugged in → the mode you had | — |
| `auto_game` | a fullscreen game turns blur/shadows/animations off, live | — |
| `night_light` | warm screens sunset→sunrise (K.night lat/lon in user.lua); the center's Night Shift still works in between | — |
| `persistent_size` | floating apps reopen at the size you left them | — |
| `hold_super` | hold Super alone ~0.9 s → Shortcuts panel while held | Super (hold) |
| `wobble` | a little spring in windows you drag | — |
| `overview` | Mission Control: every space of this screen, its windows live; drag a window onto a space to move it | Super+Tab, 4-finger pinch in |
| `resize_mode` | arrows resize until Enter/Esc (Shift = faster, −/= column width) | Super+Ctrl+S |
| `remember_place` | floating apps reopen where you left them on the screen | — |
| `pip_dodge` | picture-in-picture slides away from the pointer; hold Shift to reach it | — |
| `focus_sessions` | 25 min of Do Not Disturb, then a nudge (`kuwai focus 50`) | Super+Ctrl+G |

Overrides that must apply before kuwai loads go in an optional
`~/.config/hypr/features.lua` (`kuwai.K.features.wobble = false`).

Context keys: Super+[ / ] = previous/next (tab in a group, window in monocle,
column on the tape, else window); Super+J = rearrange for the layout; Super+Esc
= the window that needs you, or back. Screens: Ctrl+Alt+Tab next screen,
Super+Ctrl+Alt+←/→ window to that screen, Super+Shift+Alt+←/→ workspace to it.

## How it's built (and why)

- **Never block the compositor.** Hyprland runs the whole config, every bind
  and every event handler on its event loop with a ~1.5 s budget. kuwai reads
  only sysfs/tmpfs/config files and spawns everything else with `hl.exec_cmd`.
  No `io.popen`, no `lspci`/`nvidia-smi` (they wake a sleeping dGPU).
- **One broken module isn't a broken desktop.** Each module loads through
  `K.load`; a failure becomes a notification and a line in
  `~/.local/state/kuwai/errors`. If kuwai itself can't load, the entry file
  still binds a terminal, close, workspaces and quit.
- **Lua instead of scripts** where the compositor already knows the answer:
  float/pin/PiP/zoom/close-Steam, browser popups, the dictation Escape guard.
  No process, no `jq`, no race with focus-follows-mouse.
- **Static rules for placement, never spawn-then-move.** Windows map where
  they belong (floating, centred, sized) instead of jumping after they appear.
  Browser popups are the one dynamic case: `window.open_early` enables a float
  rule just for that window, before rules run.
- **Timers start after the compositor is up** (`K.defer`): a timer created
  while the config loads crashes `Hyprland --verify-config` on exit (0.57).
- **Modes are applied last** and a mode switch is a reload, so leaving a mode
  restores exactly what the theme and `user.lua` said.

## GPU

`auto` renders on NVIDIA when a screen hangs off it at login (the Acer on DP-3,
or the panel when the MUX gives it to the dGPU), otherwise on the Intel iGPU so
the dGPU can sleep. Card numbers are resolved from sysfs every login, never
hard-coded (`card0`/`card1` swap between boots). NVIDIA's VA-API/GLX variables
are set only when NVIDIA composites; on an iGPU session `prime-run` sets them
per app (forcing them globally breaks Chromium video on hybrids).

## Screens

`monitors.lua` matches screens by description, so a port change doesn't
matter. The Acer runs 2560x1440@200 in 10-bit (`XBGR2101010`; smoother
gradients under the glass) with VRR for fullscreen content; screenshots and
screen sharing stay 8-bit (`misc.screencopy_force_8b`). The panel is 4/3 scale:
exactly 1920x1080 logical.

## Themes

HyDE's switcher (or the island's Themes panel) writes
`~/.config/hypr/themes/theme.conf` + `colors.conf` and runs `hyprctl reload`;
`kuwai/theme.lua` reads both, coerces each value to the live option's type and
applies it. Rules, `exec`, `source` and animations in a theme are ignored
(kuwai owns motion and rules). No full-screen shader is applied unless you pick
one on purpose: even a pass-through shader costs a pass per frame and disables
direct scanout.

## Upgrading Hyprland

1. `kuwai doctor` after the update — it runs `Hyprland --verify-config`.
2. Option renames show up as `unknown config key`; rule effects are checked
   against Hyprland's own tables by the audit in the doctor's verify run.
3. Scripts: anything calling `hyprctl dispatch <name> <args>` or
   `hyprctl keyword` is pre-0.57; use `hyprctl dispatch 'hl.dsp.…'` and
   `hyprctl eval 'hl.config({…})'`. The doctor greps for these.

## When it goes wrong

- Session with only a cursor: Hyprland loaded the wrong file. `HYPRLAND_CONFIG`
  must be unset or point at `~/.config/hypr/hyprland.lua` (HyDE used to export
  its hyprlang file there — fixed in `~/.config/zsh/conf.d/hyde/env.zsh`).
- `kuwai doctor` says kuwai isn't what Hyprland loaded: log out and back in.
- From a TTY: `Hyprland --verify-config -c ~/.config/hypr/hyprland.lua`.
- The pre-Lua config is in `~/.config/hypr/legacy-hyprlang/` and, complete,
  in `~/backups/hypr-pre-lua-2026-11-01/`.
