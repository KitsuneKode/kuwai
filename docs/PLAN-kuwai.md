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

## STATUS (2026-11-06 late) — ratings and what gates 9.5

Notch rest 9.3 · hover 9.0 · Usage 9.3 · Bluetooth 9.0 · bell list 8.8 ·
center 8.8 · screensaver 9.0 · updates 9.0 · clipboard 8.5 · lock/login 6.5 ·
CPU 9.2 (idle ~3 %) · memory 8.8 (290–380 MB plateau, no per-open leak:
60 opens of a panel ended lower) · reliability 8.5 (3 load outages today,
gates now: offscreen load test + anchor-line names) · consistency 8.0
(tokens: sizes 62, durations 111, hex 70).

Gating 9.5, in order:
1. Lock/login: user runs the GRUB line, then the seamless greeter → shell handoff.
2. Panel-level load check before promote (TestHook compile of changed panels
   in a throwaway shell, or a headless compositor).
3. Tokens to zero: sizes (62) and the remaining durations (111) by meaning.
4. Clipboard onto the island's row/header style; one Row/Header component
   shared by NotifsPanel, T3Panel, BluetoothPanel, UsagePanel.
5. Notifications: a chat's burst folds into one card with a count; toast →
   its row in the center as one motion.
6. Verify by eye: hover pill reveal, GPU/Temp page turn, back-soon mark,
   "Claude is back" moment, dim restore (test running in background).
Not possible: one decoder for both screensaver screens (QML can't feed a
second VideoOutput; a texture can't cross windows). Freed on wake anyway.

## NOW (2026-11-06) — state, monitors, consistency

Done today: device cards for jack/USB, bell list as island panel "notifs",
pull down to read, readable() markdown, calm stepping ring (Theme.stepMs),
update watchdog race (a finished run read as "stopped"), screensaver film on
every screen, Bluetooth menu keepOpen + island panel "bluetooth", LiquidRim.

Open:
- [ ] Audits running: Grok 4.7 (state reconciliation), Gemini 3.8 Flash
      (multi-monitor), Composer 2.5 (clipboard, links, markdown). Fix what verifies.
- [ ] Notification center adopts the island look (LiquidRim, row style of NotifsPanel).
- [ ] Usage limits in the notch: review the delegate's worktree branch, merge.
- [ ] Login/lock: user runs the GRUB line (docs/manual), then a seamless greeter→shell handoff.
- [ ] **Design consistency (token migration):** every raw size/duration/hex
      onto Theme tokens (bin/rice-tokens ratchet: sizes 62, durations 131,
      hex 70 → 0); one row style (NotifsPanel/T3Panel/BluetoothPanel: 46 px,
      Theme.r2, 0.07 hover) used by the center, launcher, clipboard; one
      header style (tTitle3 semibold + right meta in tFootnote tertiary); one
      empty state (glyph + tSub line); one button set (PillButton, RestMark).
      Migrate file by file, lowest-traffic first, screenshot before/after.
- [ ] Long uptime: read ~/.local/state/rice/memlog.tsv after 2+ days; find what grows.
      Measured 2026-11-06: fresh 288 MB; ~3 MB kept per island panel open
      (17 → 33 opens: 433 → 480 MB). Find what a closed panel's Loader keeps.
- [ ] Load gate covers singletons only: offscreen stops at the first
      PanelWindow, so panel-level errors (UsagePanel's FINAL override) still
      pass. Next: compile changed panel files through TestHook before switching.
- [ ] Screensaver clock: confirm both screens move (couldn't watch 75 s live).
- [ ] Gemini audit, rejected after checking: lock covers every screen
      (WlSessionLock instantiates its surface per screen); `hyprctl repl`
      answers its argument (6 ms). Open: external monitor dim on idle (DDC).

## NOW (2026-11-05 night) — road to 9.5, see docs/design/STATES.md
Done: live shell runs from `stable` (349 MB, was 652 from dev reloads); shared
components/Popover (bell quick list on it); AssistantOverlay built only while
used; udiskie off (KUWAI_UDISKIE=1); Night screensaver; Cider ♥ / link action.
Next (2026-11-06):
1. Memory over a long session: ~550 MB after 6 h even with glibc arena_max=2
   (flat at idle, so held, not leaking). Find what holds it: image caches
   (notification icons/avatars, art), Notifs history objects, the JS heap;
   sample Pss_Anon per surface opened. rice-check's memory gate blocks
   promote after long sessions until then (promote --force restarts).
2. kittymux premium pass: running in its own thread (wave3-premium on top
   of PR #12/wave2); review its PR when it lands.
3. Login gap: user's GRUB line (vt.global_cursor_default=0
   systemd.show_status=false nvidia_drm.fbdev=1); wl-clip-persist install.
4. Token migration module by module (sizes 62, durations 165, hex 70).
5. Bluetooth pairing screen (blueman until then); T3 thread deep link when
   T3 ships one (t3code:// has no thread route today).

Status (2026-11-05, late):
1. Reload leak: neutralised. Stable shell has Quickshell.watchFiles=false and
   `rice promote` restarts it (fresh process). Root cause still unknown (dev
   only); find it with a nested/headless compositor when one is installed.
   Promote also lints changed QML (qmllint) and refuses code that won't load.
2. Lazy panels: done (Center warms on open, cools after 3 min; Overview
   LazyLoader; Assistant built on open; Clipboard mapped on purpose).
3. States: Updates skeleton, Wi-Fi (off/scanning/none found+Rescan/no match),
   launcher and clipboard empty states, bell quick list empty state. Left:
   Bluetooth pairing screen (blueman until then).
4. Tokens: bin/rice-tokens ratchet in rice-check (baseline in
   docs/design/tokens-baseline.json, only goes down). sizes 62, durations 165,
   hex 70. Keep migrating module by module; run `rice-tokens --update` after.
5. Popovers: bell on components/Popover; status menus on TrayMenu;
   AgentStack keeps its own popup on purpose (marks fly into rows).
6. Super+N: already island = quick switch, Center = deep list (+ passwords).
7. Login gap: needs the user's GRUB line (see below); then seamless handoff.
8. Clipboard: copies vanished when the copying window closed (drop-down
   kitty is its own process); wl-clip-persist starts at login once installed.
9. Later: Wallpaper Engine video wallpapers (owning WE + steamcmd, or
   licence-clean sources); meters baseline-align.

## Earlier — in progress
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

## Done 2026-11-02 (midday)
- voxtype UI hosted in the island shell (modules/voxtype/VoxtypeHost) via the fork's new
  VOXTYPE_OSD_HOST handshake (src/bin/voxtype_osd_quickshell.rs, uncommitted in the fork;
  installed to ~/.local/lib/voxtype-fork, old binary in ~/backups; drop-in
  ~/.config/systemd/user/voxtype.service.d/kuwai-osd-host.conf). Falls back to voxtype's own
  Quickshell if this shell is gone >5 s. Saves ~400 MB.
- Center opens on the clicked screen / Hyprland's focused one; tray menus dismiss (leave 650 ms,
  idle 6 s, outside click); TrayMenu also takes plain action lists (one menu everywhere).
- Clipboard: grows from / folds into the island shape (no label-pill flash), sized surface.
- Updates quick routes: chip right-click (review · update everything now [confirm, AUR
  --unreviewed] · sysup · check), launcher entries.
- kuwai-agent + Super+Alt(+Shift)+Return: Claude/Codex in the focused terminal's folder
  (kittymux tab in kitty, else new kitty); launcher "Claude here / Codex here / Agents".
- RaisedButton (Kobra plate) shared by Updates + prompt (vendored).

## NEXT (from 2026-11-02 asks)
- Icons: install `ttf-material-symbols-variable` (user, root) → AnimatedIcon component (FILL
  0→1 + weight on active/hover, 160 ms; never looping decoration); replace Nerd glyphs in the
  island/panels progressively. Keep Nerd Font for brand/app glyphs.
- RaisedButton everywhere a primary action exists (Settings, Power, Clipboard actions); PillButton
  → secondary raise.
- Steal list (clones in Claude scratchpad refs/): DMS process list + control center polish,
  dock, notepad; Caelestia dashboard (media + perf + weather), lock with media; end-4 AI sidebar
  (cheap LLM: Groq/OpenRouter free) and overview live previews; Omarchy menu tree + snapshot.
- Workspaces: drag-to-pill is not possible (layer surfaces get no window DnD); keep
  Super+Ctrl+Alt+←/→ (window to screen), +Shift (workspace to screen), Ctrl+Alt+Tab (screen).
  Idea: pills show a tiny dot for windows that need attention; Mission Control drag between
  screens.
- Settings additions: Updates (done), Workspaces (count, per-monitor on/off), Agents (default
  agent, kittymux tab vs window), Voxtype host on/off, Icons (Material/Nerd), Buttons/motion.
- oxf-cli (~/Projects/cli-tools/oxf-cli): separate session — UX/UI, corpus, images, cheap LLMs.

## Done 2026-11-02 (afternoon)
- voxtype fork commit 9446e6c (VOXTYPE_OSD_HOST); island reclaims after a fallback (tested:
  kill shell → voxtype's own OSD in <8 s → shell back → it takes over again).
- Motion: Theme.surfaceIn/Out/KeyIn/KeyOut used by island, clipboard, Quick Look, overview.
- Toasts go to the screen under the pointer (Screens.underPointer).
- Super+Ctrl+←/→ workspaces, +Shift carry, ↑ Mission Control, ↓ first empty (own block);
  resize → Super+Alt+arrows.
- AUR standing via AUR RPC (votes, popularity, maintainer, age, out-of-date → "established");
  auto-approve needs established + routine + nothing flagged.
- Clipboard @-filters, pins in place by time (setting), Clipboard settings page.
- Island Wi-Fi / battery right-click menus (known networks, Wi-Fi toggle, nmgui; kuwai modes,
  time left, Power…). Lock screen has no menus.

## NEXT (2026-11-02 afternoon asks)
- Switcher: snappy's context mode (group by app+workspace, stacked card, cycle within),
  Super+Alt+Tab = this workspace's windows; then uninstall snappy-switcher.
- Icons: Phosphor (thin…fill + duotone; MIT) into ~/.local/share/fonts (no root), a DuoIcon
  component (two layers: 20% back + front), state animations only (fill/weight, 160 ms).
  Material Symbols variable is the alternative (needs pacman).
- Apple roundness: a Squircle component (continuous corners, like NotchShape) for cards,
  panels, toasts; capsules stay capsules.
- Glass: one material pass (GlassCard + Elevation) across island surfaces, toasts, center.
- Notifications: full UX pass (grouping, actions, inline reply, image previews, swipe).
- Weekly AUR digest (optional cheap LLM: Groq/OpenRouter free) reading upstream release notes
  for non-established packages; Omarchy's package repo as a future source of vetted builds.
- From the T3code session (not done yet): hover-scroll volume/brightness on the island,
  Bluetooth pages (saved/nearby/pair), squircles, dock, installer + folder layout, shaders,
  clipboard pin folders + encrypted secrets vault + dedupe review, native chat window
  (docs/CHAT.md), cava visualiser, kittymux pane title bars / tab thumbnails / progress.
- Live-desktop rule (from that session): batch shell restarts; don't open the user's panels
  or move focus to test; verify with logs, state and off-screen where possible.

## Audit 2026-11-02 (memory, leaks, primitives)
Measured (PSS): shell ~400 MB at start → ~530 MB after opening heavy panels, then flat
(6 samples over 3 min: 529–536 MB) = caches, not a leak. Anon 442 MB, file 107 MB.
rice-auth 127 MB, brightness daemon 20 MB, voxtype launcher 3 MB, watchers <1 MB each.
Leak scan: every dynamic Process (Clipboard pinner/runner/capturer/thumber/texter,
Display, Kittymux, SoundView, Notifs jumper) destroys itself on exit; notification items
destroyed on removal; Switcher MRU capped 200; Updates log capped 400. OK.
Fixed today: variable SF Pro mapped ×15 (−200 MB RSS); voxtype 2nd Quickshell (−400 MB);
clipboard surface stale frame; bare watchers dying silently (now a service).
To do (memory): unload panel content on close (Loader active only while shown + 10 s),
cap image cache for thumbnails (sourceSize everywhere, cache:false for one-shots),
release Updates.reviews after a run (done) and on panel close.
Primitives to consolidate (no duplication):
- components/Chip, Notice, Card (now local to UpdatesPanel) → shared
- PillButton → RaisedButton kind "secondary" (one button)
- Nerd-glyph Text → components/Icon (Phosphor) everywhere
- inline spring tiers (Capsules, LockView) → Theme tokens
- 5 services each declare a `runner` Process component → one services/Run (exec + callback)
- kuwai state file read in Island and IslandStatus → one services/Kuwai (mode, model, features)
- TrayMenu (popup) + ActionMenu (in-panel) share one item model already; keep both surfaces
- ~/Scripts dependencies (brightness.sh/py) → move into the repo for distribution

## NEXT (2026-11-02 evening asks)
- Island theming: accent source option (theme · voxtype palette #66C7FF #86E0B4 #F2CC4D
  #FF7A98 #F2594D), two-stop gradients (accent → hue-shifted neighbour) on the lit pill,
  rings, progress and the raised button; glows tinted; keep the body near-black.
- Browser scripts in ~/Scripts: review, fold the good ones into kuwai (launch-or-focus,
  profiles, tabs → launcher), drop the rest.
- Shortcut menu (Super+/) and key scheme review after the reboot.

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
