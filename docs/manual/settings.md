# Settings

Open Settings with **`Super+Ctrl+I`**, from the launcher (`Settings`, or any setting name such as `idle`, `screensaver`, or `24-hour`), or with `kuwai settings [section]`.

Changes apply immediately and are stored in `~/.config/kuwai/settings.json`, validated against [shell/config/settings-schema.json](../../shell/config/settings-schema.json). Every modified row shows a reset action to return to its schema default.

## Sections

| Section | ID (`kuwai settings <id>`) | What it configures |
| --- | --- | --- |
| Bar & Island | `bar` | Top bar (`island` or `waybar`), notch vs floating shape, split capsules, rest workspaces/status/media/weather, hover delay and view |
| Clock & Date | `clock` | 24-hour clock, show seconds |
| Notifications | `notifs` | Peek vs toast routing, hide sensitive chat text, fullscreen notifications, how long seen rows stay |
| Assistant | `assistant` | Opt-in switch for the local Ollama assistant, model selection |
| Accessibility & Motion | `motion` | Reduce Motion, Increase Contrast, Text Size (100%–200%) |
| Keyboard | `keyboard` | Keyboard layouts, switch shortcut, key repeat, function keys (`kuwai` vs `plain` for F7/F8/F10) |
| Shortcuts | `shortcuts` | Rebind any kuwai shortcut by pressing the new chord (`~/.config/kuwai/keys.tsv`) |
| Mouse & Trackpad | `pointer` | Pointer speed, acceleration, natural scrolling, tap-to-click |
| Displays | `displays` | Monitor resolution, refresh rate, scale, and display presets |
| Island Behaviour | `island` | Minimal vs everything at rest, reveal on approach, limit alerts threshold, idle project threshold |
| Workspaces | `workspaces` | Minimum workspaces shown, per-monitor workspace behaviour |
| Power & Idle | `power` | Idle dim, lock, screen-off, and suspend timeouts on AC and battery |
| Screensaver | `saver` | Style (`still` by default, `live`, `dusk`, `borealis`, `night`, `photos`, `flow`), when it runs (`always` before the fade and lock by default, `caffeine`, `off`), timeout, Night clip, photo interval and folder, the long-wait black clock |
| Reminders & Alarms | `time` | Alarm sound, snooze, Pomodoro lengths, Focus on work blocks |
| Clipboard | `clipboard` | History behaviour, secret masking |
| Software Update | `updates` | Check interval (`0` = only when opened), Flatpak inclusion, routine AUR bump approval, post-update cache pruning |
| About | `about` | Version, channel, restart shell |

## Command-line settings

Use `kuwai set` and `kuwai get` (backed by `bin/kuwai-settings` with file locking and atomic rewrites):

```sh
kuwai get                       # print current settings.json
kuwai get clock24               # read one key
kuwai set clock24 false         # update one key immediately
kuwai set textScale 1.25        # scale UI text (1.0 to 2.0)
kuwai-settings reset clock24    # remove override and revert to schema default
```

## Background collection (`kuwai collect`)

Clipboard history and GitHub/Gmail notification feeds are off by default and stored in `~/.config/kuwai/collect.conf`:

```sh
kuwai collect                   # show current clipboard and feeds state
kuwai collect clipboard on|off  # enable or disable kuwai-clipboard.service
kuwai collect feeds on|off      # enable or disable kuwai-feeds.service
```

## Desktop modes and automatic features

Desktop look modes (`hypr/kuwai/modes.lua`) and Hyprland automatic features (`hypr/kuwai/features.lua`) are controlled separately from `settings.json`:

```sh
kuwai mode list                       # focus · default · glass · gaming · battery
kuwai mode glass                      # switch desktop mode
kuwai motion full|reduced|off         # Hyprland motion tier
kuwai feature                         # list automatic Hyprland features
kuwai feature wobble off              # disable one automatic feature
kuwai gpu auto|nvidia|intel           # choose compositor GPU for the next login
```

See [docs/SETTINGS.md](../SETTINGS.md) for the full schema and concurrency contract.
