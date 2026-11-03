# What was asked, and where it stands

Rebuilt 2026-10-30 from every message in the long working session (117 of them, read back from the
transcript after context compaction lost some). One line per request; status is the truth as of this file.
Keep it current: tick things off in the commit that does them.

## Done
- Notifications as our own layer (toasts on the focused monitor, Sonner mechanics, center with tabs,
  agents tab, sound mixer with colours, brightness/display tab, usage like t3code with multi-account).
- SF Pro / SF Pro Rounded / SF Mono throughout; Apple-style motion (Emil, fluid functionalism).
- Shortcut sheet as a floating menu (not a tiled window); center layout overlaps fixed.
- Clipboard island (Super+V): images, Quick Look, markdown/code/mermaid rendering, open with default
  app, date filter (yesterday, five days ago…), pins, save-as, OCR.
- Notification jump focusing the exact window (no workspace jumps on the other monitor).
- Screenshots: Super+P annotate, quick, window, OCR, delay, freeze; satty focus; cancel is silent.
- Screen recording island (GPU encoder, source/audio/fps setup, stop ring, saved pill).
- kittymux: precise focus, kitty capability research, OSC 7501 relay, tab progress (OSC 9;4).
- The island: rest, hover, live activities (voxtype, Shazam, music, mic dot), panels (calendar, power,
  launcher, settings, system, themes), alerts, lock screen with media, Waybar's modules.

## Pending (oldest first)
- Native chat app: the local agent and its UI are built (2026-11-03: tools, approvals, reasoning,
  model picker, context chips, / commands; plan in docs/superpowers/plans/). Still open: real web
  search, auto-compaction, the ChatGPT/Claude subscription backends (docs/CHAT.md).
- Audio devices with real product photos (the Audiocular DAC) in the sound picker.
- Shaders (screen and per-surface), used sparingly; use the GPUs well without waking the NVIDIA one.
- Hyprland 0.57 port (when it's installed here; 0.56.2 now); monocle and scrolling layouts.
- Installer + folder structure so others can use the rice; settings app grown to every surface.
- Popups unified with the island (center from the island or the right: configurable).
- Lock screen: animated background options; make it the default after it's proven.
- Clipboard: nested pin folders, encrypted vault, multi-select, return to the last position.
- kittymux: Rex-level UI (see below), tmux-level sessions, kitty graphics protocol, Gemini later.
- Voxtype OSD font (check it uses the same type as the rice).

## This round (2026-10-30)
Done since: floating island default + Shape setting; pills like the reference (narrower inactive);
centred SF Pro time; hover not expanding over pills; special-workspace ring; three-column expanded
island with level waveform; per-item tooltips; tray trimmed; animated stats; updates moment; launcher
crash fixed + browse all apps; clipboard one-notch-one-item + ⌥← last position; Mac key glyphs; lock
screen after the reference (press any key → password pill); themes grow open + large preview;
shortcuts panel from Hyprland binds (Super+/).
Still open from this round: clipboard multi-select; night light in the notification panel; the
center growing out of the island (configurable); kittymux Rex-level UI.

- Island default = floating dynamic island (the photos), notch as an option.
- Workspace pills like the reference: equal widths, dim inactive, glowing active, tighter group spacing;
  hover over the pills must not expand the island; a distinct animation for special (hidden) workspaces.
- Clock in SF Pro (not rounded), medium weight, exact spacing; status icons and battery in the accent.
- Expanded island like the reference: app + pills left, time/date chip (opens calendar) + media centre,
  notifications + status right; media with real level waveform and controls; stats where they help.
- Tooltips per item (network ≠ battery); trim tray icons we duplicate (nm-applet, blueman, udiskie).
- Stats: values animate when they change; colours follow load.
- Updates available as an island activity (Skiper-style), then a badge.
- Springs with a little bounce; Apple spacing.
- Lock: a hang reported (UI froze while typing): investigate logs, make it robust.
- Clipboard: one wheel notch = one item, fast; macOS-style key glyphs (⌃ ⇧ ⌥ ⌘); multi-select; return to
  the last position.
- Launcher: browse all apps (not only search).
- Themes/wallpapers: animated open/close, a live wallpaper preview.
- Shortcut menu from the Hyprland binds; architecture notes.
- Notifications: dismissed ones are not kept (as macOS); expired ones go to the center.
- Night light visible in the notification panel's controls.
- kittymux: group tabs by session (folders, stable) with a pinned "Needs you"; Rex-level UI: tab pills
  with icon chips, pane title bars with split/zoom/close, session switcher ("Filter or create…"), command
  palette, tab previews with thumbnails, find bar, sliding hover highlight.

## 2026-11-01 — Hyprland 0.57 Lua port (kuwai)

Done: hyprlang → Lua (`hypr/`, `bin/kuwai`, docs in `hypr/README.md`); shell
dispatch calls and scripts moved to Lua syntax; backups in
`~/backups/hypr-pre-lua-2026-11-01/`. Next: log in again (the running session
still has HyDE's old config path cached), then `kuwai doctor`. Roadmap in
`docs/KUWAI.md`.
