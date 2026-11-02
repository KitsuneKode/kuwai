# kuwai — working plan (kept across sessions)

Written 2026-11-01 so the plan survives context compaction. Tick items here as
they land. User wants: extremely secure, premium, tasteful, fast, Apple-grade.

## Skills the user asked to be used (load with the Skill tool when working on the matching area)
/animate · /emil-design-eng · /apple-design · /interaction-design · /interface-design ·
/improve-animations · /find-animation-opportunities · /review-animations · /ask-sonner ·
/break-ui · /better-colors

## Rules learned (also in memory)
- Never type synthetic text into the live session (ydotool/wtype) to test; screenshots, logs,
  `hyprctl dispatch 'hl.dsp.global("rice:…")'` instead. Ask first for key chords.
- Island panels hold exclusive keyboard: focus other windows only after the panel closes.
- Surfaces that *are* the island: `ExclusionMode.Ignore`, start from `Island.restWidths[screen]`.
- Hyprland reaps children: no `os.execute` exit codes inside kuwai; no popen in hot paths.
- Timers in kuwai: create via `K.defer` (verify-config crash otherwise).

## NOW — in progress
1. **Polkit agent (rice-auth)** — BUILT 2026-11-01: shell-auth/shell.qml + systemd/rice-auth.service
   (linked into ~/.config/systemd/user, started by startup.lua; hardened: no crash handler/dumps,
   LimitCORE=0, NoNewPrivileges, no file watcher, software renderer ~140 MB, exit 3 = another agent
   → OnFailure KDE agent). Picks *your* identity when polkit offers several; submits only when PAM
   asked. Remaining: user runs `pkexec true` (enter + Esc paths), `kuwai auth` subcommand
   (install/status/test), doctor check. Original brief: — island-styled, *separate small Quickshell process*
   (`shell-auth/`, own systemd user unit, Restart=on-failure), Quickshell.Services.Polkit
   (PolkitAgent/AuthFlow → polkit-agent-helper-1; never handle the password ourselves; clear
   field on close; no logging; show action id + requesting program + user; Overlay layer,
   exclusive keyboard, dim backdrop; queue while locked; fallback: start
   plasma-polkit-agent if rice-auth fails to register). Replace plasma-polkit-agent in
   kuwai startup. Test with harmless `pkexec true` / dry runs before going live.
2. **Updates panel in the island** (no kitty/sysup spawn; sysup stays for terminal):
   list repo + AUR updates (checkupdates, paru -Qua), per-package toggles, release notes,
   Update selected/all; repo via pkexec pacman (prompt = rice-auth), AUR builds as user,
   install step via `paru --sudo pkexec`-style; inline progress + "show log"; no NOPASSWD,
   no stored passwords, no blanket polkit rules. Replace the "Details → System → terminal" flow.

   Design decisions from studying Omarchy / DMS / Caelestia / end-4 (2026-11-01):
   - Arch repo packages upgrade **together** (`pacman -Syu`, never per-package = partial upgrade;
     DMS enforces the same). Toggles apply to **AUR** packages only; repo list is shown read-only
     with an optional "hold" that warns.
   - Repo step: `pkexec pacman -Syu --noconfirm` in one auth (DMS does this). AUR builds run as
     the user (makepkg must not be root); paru's install step via `--sudo pkexec`-style; show
     the PKGBUILD diff link for AUR changes (AUR is unvetted code).
   - Pre-flight like Omarchy: ≥10 GiB free on /, keyring first (archlinux-keyring), Arch news
     check for manual-intervention items, battery/AC check, stay-awake inhibitor during update.
   - After: kernel updated → "Restart needed" (compare `uname -r` with /usr/lib/modules),
     services needing restart, `.pacnew` files (pacdiff) surfaced, log kept in ~/.local/state.
   - No snapshots possible (root is ext4, no snapper) — say so; don't pretend recoverability.
   - Lock screen: rice lock uses PAM "hyprlock" (includes system-auth → faillock works).
     Caelestia ships its own pam.d with faillock + optional fprint/howdy — borrow fprint later.
   - Omarchy ideas worth keeping: ufw deny-incoming (already enabled here), faillock limit
     tuning (deny=10/unlock 120 vs Arch default 3/600) — user's call, needs root, propose only.

## Done 2026-11-02 (night)
- rice-auth v2: grows out of the island's exact rest shape (shell publishes
  $XDG_RUNTIME_DIR/rice/island.json), island springs, Theme tokens (config/ components/
  assets symlinked), avatar (~/.face rounded via magick), tries left + lockout countdown from
  faillock, Caps Lock tag, success check, accent buttons. Software renderer (no MultiEffect /
  ClippingRectangle there). Tested with pkcheck (pkexec can't run in Claude's sandbox).
- Cancel counts as a faillock failure (polkit socket helper; KDE's too) → tell user; propose
  deny=10 unlock_time=120 (Omarchy). User must run it (root).
- Screens.focusedName went stale (Quickshell focusedMonitor) → panels opened on the other
  monitor holding exclusive keyboard = "launcher stuck" / likely the vicinae Super+Space issue.
  Now tracked from raw events + hyprctl probe before every keyboard open.
- Theme picker: palettes on cards + preview strip; Colours mode (theme/wallpaper/dark/light =
  HyDE enableWallDcol via `rice-themes colormode`); stable fav sort; island surface 1120 wide.
- Theme.qml: accent follows HyDE mode (theme.dcol → kitty.theme → wall.dcol), 400 ms blend,
  Theme.onAccent. Island rest: no padding hole beside the time (balanced only within 10 px).
- Pills: current = numbered capsule (iOS page control); guests hollow after a gap.
- Keyboard-opened panels morph too (fast critically damped tier) instead of snapping.
- Media card: click → focus the playing window (title/class match, else MPRIS raise);
  right-click → sound panel.
- Tray menus: components/TrayMenu.qml (QsMenuOpener, drill-down submenus, theme glass).
  NOT yet seen by eye — ask user.
- config/Paths.qml: no hardcoded ~/Projects/rice in QML. doctor checks rice-auth + faillock.

## Decisions / answers given
- AUR in Updates panel: review ON by default and never silently skipped: per-package PKGBUILD
  diff (git diff in paru clone cache) shown in-island with a reusable DiffView/CodeBlock (QML;
  diffs.com/shadcn patterns ported — the shell is QML, not web: no CSS/shadcn directly);
  "Approve" per package; option "trust updates from this package" is explicit per package.
- Login: recommend greetd + a Quickshell greeter reusing the rice lock (DMS's dms-greeter
  approach) so login → lock look identical; SDDM (astronaut theme now) stays until tested.

## Done 2026-11-02 (morning)
- Software Update: bin/rice-update (+ detached systemd job kuwai-update: survives shell restarts,
  pacman writes to a file not a pipe, single-instance lock, inhibits sleep/shutdown), Updates
  service (follows update.jsonl, rejoins after restart, watchdog), UpdatesPanel (list / review /
  run), DiffView, island ring + %, hover chip, alert "Review", System row. Routine version bumps
  detected (versions/hashes normalised). Review = diff since the commit that built the
  installed version. One island Back row (Island.innerBack) for panel levels.
- rice-auth: vendored tokens (no links), `kuwai auth diff|status`, doctor audit (no IPC/process
  in config/components, 4 known commands), pacman prompts named "Install system/AUR updates".
- Shell started via Hyprland (rice-shell), not as a child of whatever terminal ran it.
- Fonts: static SF Pro Text/Display (948 → 741 MB RSS; variable SF-Pro.ttf no longer mapped ×15).
- Accent: Theme.vivid() keeps the theme hue, S ≥ 0.6, L 0.62–0.74 (voxtype HUD band).
- Pills back to the reference (taller lit pill, no numbers; hover tips; Super+Tab for all);
  pill scroll = kuwai.ws_step (same as Super+Alt+←/→); guests step from the block start.
- Clipboard: lands on the neighbour after pin/unpin/delete; multi-select (⌃-click, ⇧-click,
  ⇧←/→, ⌃A, Esc) with pin/delete/copy/paste on all; inline status, no toasts.
- Brightness (~/Scripts/brightness.py, backup in ~/backups): external monitor ramps in eased 1%
  steps through libddcutil (~70 ms/write), handle released after each ramp (bus lock).

## NEXT (added)
- Move voxtype's MeetingControls/EnginePicker into the island, then `[osd] enabled = false`
  (its own qs is ~400 MB); user's call (voxtype is their project).
- Main shell anon memory ~255 MB: profile images/thumb caches, Loader-unload heavy panels.
- Rename rice → kuwai (units rice-auth/kuwai-update, bins, layers) in one pass.

## NEXT
3. One switcher UI for Super+Tab and Alt+Tab (Mission Control = zoomed-out view of the same
   surface); windows grouped by workspace; apps with many windows = one stacked card with
   count, Alt+` expands; extremes (0, 1, 50+ windows, long titles, no icon).
4. Settings panel: features (kuwai feature list), modes, weather location/toggle, GPU choice,
   night-light schedule, switcher options, tooltips everywhere; consistent with island.
5. Review pass with the skills: motion (/review-animations, /emil-design-eng, /apple-design),
   /break-ui worst-case data on launcher, palette, switcher, notifications center, clipboard;
   /better-colors on palette/gradients/accent; /ask-sonner on toast stack.
   Animation verdicts so far — keep: island morph (critically damped now), launcher/palette
   materialize + first-paint cascade, clipboard/HUD grow from island, toast stack, switcher ring.
   Removed: wobble, motion blur, borderangle loop. Improve: special-workspace slide (match
   island spring), notification-center open/close, Mission Control zoom-out-from-workspace.
6. Notification center: review missing/wrong bits (null-guarded CenterRow done), liquid glass.
7. HUD (volume/brightness): grows from island; flick up / right-click dismiss (done) — verify feel.
8. Tooltips as popups (done in components/Tip.qml) — verify visually; tray right-click (needs
   QApplication pragma, done) — verify.
9. Island alert banner: Details clickable while hovered (done) — verify.
10. Rename rice → kuwai in one pass with aliases (layers rice-*, global shortcuts rice:*,
    bin/rice*, ~/.local/state/rice); entry already finds ~/Projects/kuwai.
11. Undecided by user: 10-bit on the Acer after relog; colour-accurate vs vivid; drop
    voxtype's separate pill (island already shows dictation, saves ~150 MB); make rice lock
    the default lock.
12. Later ideas: dashboard (weather/media/perf) from the island, process list (DMS), notepad,
    dock, wallpaper blur when covered, installer + README + video (viral), Stage-Manager-like
    Lua layout.

## Done this session (for orientation)
Hyprland 0.57 Lua port (hypr/, bin/kuwai, doctor), GPU auto, VRR per-window fix, permissions
gating, HYPRLAND_CONFIG fix + shim, features/modes, Mission Control, palette (Super+/ & hold
Super), launcher selection fix, island switcher (Alt+Tab), clipboard/HUD from island,
workspace pills + guests, special capsule, weather in hover, emoji/glyph modes (: ;),
satty copy fix, monitor bottom-align, resilience (clamshell, battery guard, session restore).
User still needs one logout/login.
