# The rice as one island

Status: roadmap, 2026-10-29. Built so far: the island bar at rest and on hover (`rice bar island`, step 1), the clipboard island (copy pill, shelf, Quick Look), the recording island
(setup, pill, saved), the center (notifications, agents, sound, controls), the OSD. This page is the plan for making
the island the whole shell, replacing Waybar, rofi, hyprlock's look and the scattered popups.

## The idea

One black-glass island at the top centre of each monitor (Apple's Dynamic Island, macOS notch apps, the references in
the conversation: "insane hyprland", Skiper's island, the island rice video). At rest it is a small pill with the
essentials; it grows, never jumps, into whatever is needed, and shrinks back. Everything else (control center,
calendar, power menu, launcher, settings, auth prompts, the lock screen) is the same material and the same motion,
growing out of the island or from it, so the rice reads as one object, not a bar plus windows.

## States of the island

| State | Looks like | When |
|---|---|---|
| Rest | workspace capsules · clock · signal + battery | always |
| Hover | grows to: workspace name + capsules · clock + date · media card (art, title, artist, waveform) · "All caught up"/count + bell · signal + battery | pointer on it (300 ms intent delay), shrinks on leave |
| Live activity | recording (dot, time, stop ring) · copy (pill) · timer · now playing (art + bars) · voxtype dictation · agent needs you · low battery · volume/brightness (replaces the OSD) | while it lasts; activities queue, the newest wins, others show as a small second bubble |
| Expanded | a panel grown out of the island: control center, calendar, media player, Wi-Fi/Bluetooth/Sound pages, power menu, launcher, clipboard shelf, recording setup, polkit prompt | click a part of the island, or its key |

Clicking a part opens that part: clock → calendar (week strip at first, month on a second click); status → control
center; media → player; capsules → workspace overview.

## Surfaces (each its own module, one material)

1. **Island bar** (replaces Waybar): rest/hover/live as above; workspaces from Hyprland IPC events (`Hyprland`
   singleton), not polling. Per monitor.
2. **Control center** (from the island's right): tiles Wi-Fi, Focus (DND), Bluetooth, Game Mode, Night Light, Lock;
   Sound and Display sliders with a chevron into their pages; notifications list. Pages slide in (Wi-Fi networks,
   Bluetooth devices with Connect/Pair and Scanning, Sound: outputs/inputs with device icons and checks, per-app
   volumes). Layout editable (drag, resize, add/remove), stored in settings.
3. **Calendar** (from the clock): week strip → month grid; today ringed in the accent; events later.
4. **Media** (from the media card): art-tinted card, scrubber, transport; Cider/MPRIS; art colour drives the accent.
5. **Power menu**: Lock, Suspend, Log out, Reboot, Power off; hold-to-confirm for the destructive ones.
6. **Polkit agent** (`Quickshell.Services.Polkit`): the auth prompt grows from the island.
7. **Launcher** (replaces rofi): apps (DesktopEntries), calculator, files, clipboard, windows, commands; fuzzy (the
   clipboard's matcher), frecency.
8. **Settings app**: sidebar (Bar & Island, Media, Clock & Date, Appearance, Motion, Launcher, Dock, Notifications,
   Control Center, Lock Screen, System), search, back/forward, rows of toggles/sliders/segmented controls, live preview;
   writes `~/.config/rice/settings.json`, which every module reads (one `Settings` singleton).
9. **Lock screen** (`WlSessionLock`): big rounded-numeral clock (SF Pro Rounded, animated digits), date, avatar, user,
   "press any key"; blurred, slowly moving wallpaper (a cheap shader, paused when idle/on battery); PAM via
   `Quickshell.Services.Pam`.
10. **Wallpaper & theme**: picker grown from the island (thumbnails, ←→, Enter), matugen/wallbash colours, applied to
    the rice, kitty, Hyprland borders; theme presets.
11. **Dock** (optional, off by default).
12. **Toasts** become island activities or stack under it (Sonner mechanics stay).

## Primitives (composable, shadcn-style)

`components/` grows into a small design system, each piece one job, styled only by Theme tokens:
`Island` (the morphing black-glass surface: rect + radius + spring, squircle corners), `Panel`, `Card`, `Tile`,
`Toggle`, `Slider`, `Segmented`, `ListRow`, `Section`, `IconButton`, `PillButton`, `KeyCap`, `Tips`, `Skeleton`,
`RollingNumber`/`AnimatedDigits` (skiper37-style digit roll for the clock), `ActionMenu`, `Sheet`. Modules compose
them; no module draws its own button.

**Squircle corners**: continuous-curvature corners (superellipse), not circular arcs, drawn with a `Shape` path (or a
small SDF shader) so the island's ends feel Apple-smooth.

## Structure

```
shell/
  config/        Theme, Settings (json-backed), Motion
  components/    the primitives above
  services/      Hyprland (workspaces), Media, Network, Bluetooth, Audio, Power, Notifs, Clipboard, Recording…
  modules/
    island/      Bar, Hover, Activities/*, the morph
    control/     ControlCenter, pages/*
    calendar/  media/  power/  polkit/  launcher/  settings/  lock/  wallpaper/  dock/
    notifications/  clipboard/  osd/   (existing; folded into the island over time)
bin/             rice, rice-shell, rice-clip, rice-shot, rice-rec, rice-usage, rice-render
install/         installer: packages, fonts, symlinks, Hyprland include, migration from HyDE
```

## Hyprland

- Use IPC events (socket2) through Quickshell's `Hyprland` singleton for workspaces, focus, monitors: no polling.
- 0.57: check the release notes when it lands (this machine runs 0.56.2); port config syntax and new layer rules, try
  new layouts (monocle, scrolling) and decorations (glow, motion blur, wobble) behind settings, performance-first.
- Shaders: optional screen shader (cinematic/vibrance) and per-surface effects; off by default, cheap when on.

## Order

1. `Settings` singleton + the island bar at rest and hover (behind a switch; Waybar stays until it's ready).
2. Control center with pages (Wi-Fi, Bluetooth, Sound), calendar, power menu.
3. Live activities moved into the island (OSD, now playing, timer, voxtype, agents).
4. Launcher (retire rofi), polkit agent.
5. Settings app.
6. Lock screen; wallpaper & theme picker.
7. Installer and folder restructure for others to use.
8. Hyprland 0.57 port; shaders; dock.
