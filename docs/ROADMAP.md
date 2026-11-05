# kuwai / rice: the road to 8.5

The goal: a desktop that feels like Apple made it for Linux people. Calm,
consistent, fast, safe, and with a few original ideas (the island, the
updater, agents in the notch) done better than anyone. Not more features:
fewer, finished ones.

Ratings (2026-11-05, my judgement /10): **ours 6.6** · Omarchy 7.5 ·
DankMaterialShell 7.4 · Caelestia 7.1 · end-4 6.8 · HyDE 6.1. We lead on the
island, notifications, motion, the updater and agent awareness; we trail on
install, docs, settings UI and reliability.

Each item: **what** · **done when** (the acceptance check). Phases are in
order; inside a phase, items are independent. Owners: *shell* (this
repo's shell work), *island* (the island session), *ai* (the assistant
session), *you* (needs the user).

---

## The rules everything follows

1. **One meaning per colour.** Accent = where you are / selected. White =
   status. Green = good/charging. Orange = attention. Red = bad. Art colour
   = media. Yellow = Caffeine/search matches. Nothing else is coloured.
2. **One primitive per job** (Phase 2). No panel draws its own button,
   chip, card or notice.
3. **Motion explains or it goes.** Springs critically damped; ≤300 ms for
   UI; keyboard-opened things instant or on the fast spring; reduced motion
   = fades only; enter slower than exit; never from scale 0.
4. **Nothing exists while unseen.** LazyLoader/Loader for every panel,
   window and decoder; timers run only while their output is visible; no
   polling where a file watch, socket event or signal exists.
5. **Children die with the shell.** Every long-lived Process is wrapped in
   `setpriv --pdeathsig KILL` (inhibitors, monitors, listeners).
6. **Root does one narrow thing.** Only `rice-update-root`, only installed
   root-owned, only validated requests. No shell strings built from data;
   arguments are argv.
7. **The lock is never weaker than the session.** No content leaks on the
   lock or login screen; a crash while locked stays locked.
8. **Every change lands on stable through `rice promote`**, after
   `rice-check` passes (Phase 1).

---

## Phase 1: reliability first (target: Reliability 8)

- [x] **Test hook** (`qs ipc … call test …`, dev only): inject a moment,
  a device connect/disconnect, a charger state, an agent list (working /
  waiting / done), a timer, an alert, a notification burst. **Done when**
  every island state in `docs/ISLAND.md` can be shown without real hardware.
- [x] **`rice-check`**: the shell loaded with no "caused by"; no orphaned
  helpers (inhibitors, gdbus, systemd-inhibit) outside the running shell;
  memory under budget (Pss_Anon < 450 MB idle); one sleep guard; hypridle
  off while the shell owns idle. **Done when** `rice promote` runs it and
  refuses on failure (`--force` to override).
- [x] **State screenshots**: `rice-check --shots` drives the test hook
  and saves island / toast / center states to `~/.cache/rice/shots/<commit>/`
  (never opening keyboard-grabbing panels unless `--interactive`).
- [ ] **Split the branch** (*you* + all): island moments · proximity ·
  agents · idle · updater · AI into separate PRs.

## Phase 2: one design system (target: Consistency 9)

- [x] **Primitives** in `components/ui/`: `Button` (primary · secondary ·
  danger · quiet), `IconButton`, `Chip`, `Card`, `Notice`, `Switch`,
  `Segmented`, `Slider`, `Menu`, `Tooltip`, `ListRow`, `Sheet`, `Field`,
  `KeyHint`, `Badge`, `Ring`. Built only from `Theme` tokens.
- [~] **Replace the copies** (UpdatesPanel, SystemPanel done): UpdatesPanel's Chip/Card/Notice, RowChip,
  QuickIcon, PillButton/RaisedButton, the several Segmented and toggle
  variants. **Done when** `rg "component (Chip|Card|Button|Notice)"`
  finds nothing outside `components/ui/`.
- [ ] **Tokens audit**: every literal colour, radius, duration and font
  size in `modules/` moves to `Theme` (spacing scale 4/8/12/16/24, radii
  8/12/16/22, type scale 11/12/13/15/17/22/34).
- [x] **docs/DESIGN.md**: each primitive with a screenshot, states and
  do/don't.

## Phase 3: settings you can click (target: Settings 8.5)

- [ ] Every `settings.json` key has a row in the Settings panel, grouped
  like macOS System Settings: Appearance · Island · Notifications ·
  Displays · Sound · Power & Idle · Wallpaper & Screensaver · Keyboard ·
  Privacy & Security · Updates · About.
- [ ] Search across settings; "Reset to default" per row; changes apply
  live.
- [ ] Theme switching in the shell (wallbash colours, GTK/Qt/kitty
  themes) so HyDE's rofi menus and scripts can go.

## Phase 4: performance and memory (target: Performance 8)

- [ ] **Budget**: shell idle ≤ 350 MB Pss_Anon, ≤ 2 % CPU idle, no
  per-second timers while hidden (checked by `rice-check`).
- [ ] Lazy: the assistant overlay (*ai*), clipboard thumbnails (release
  on cool-down), the Notification Center's Sound/Controls tabs.
- [ ] **AI model offload** (*ai*): unload `llama-server` after N idle
  minutes, load on first use; never run it on battery unless asked. The
  single biggest RAM/heat win (14 GB, ~3 cores).
- [ ] Screensaver: 10 start/stop cycles with no growth; Dusk under 5 %
  CPU.
- [x] Kittymux `agents.json` (kittymux plan 014) replaces the 20 s poll.

## Phase 5: productivity, the Apple way (target: Productivity 8.5)

- [x] **Quick note** (Super+Ctrl+N opens the launcher on `note `; `rice note`): from the island (hover → note) or Super+N twice; a
  sheet that saves to `~/Notes/inbox.md` (Markdown, timestamped); search
  in the launcher.
- [x] **Reminders**: "remind me at 5 to call mum" / "in 20m stretch" in
  the launcher; kept in `~/.local/share/rice/reminders.json`; an island
  moment and a toast with Snooze/Done; survive restarts and sleep.
- [x] **Pomodoro**: the timer with cycles (25/5 ×4, 15 long), a ring in
  the notch, Focus on during work blocks (optional).
- [x] **Alarm** (services/Alarms, `system/install` for rice-wake; Stop on the lock screen itself still open): a time of day that wakes the laptop (`rtcwake`/systemd
  timer with WakeSystem through the root helper or a user timer), plays
  through the lock screen.
- [x] **Clipboard**: password-manager copies never stored (cliphist reads
  the hint); keys and tokens that look secret leave history after 60 s.
  (Window-class rules for hint-less browsers: still open.)

## Phase 6: security and edge cases (target: Security 8.5)

- [ ] **AI sandbox review** (*ai*): file rules, network, which commands
  run without confirmation; a deny-list for `sudo`, `rm -rf`, `curl | sh`.
- [ ] **Lock**: shell crash while locked (stays locked, re-locks);
  monitor hot-plug while locked (Lock.qml resurface; test with a headless
  output); notification and OTP text on the lock screen (masked);
  clipboard not readable while locked; media controls only.
- [ ] **Login**: no autologin; the password never reveals its length;
  greeter has no shell or terminal reachable; failed-login back-off.
- [ ] **Updater**: root helper ops fuzzed with bad paths (symlinks,
  `..`, non-root .pacnew); sudoers only after `visudo -c`.
- [ ] **Network fetches** (weather, currency, calendars): timeouts,
  size limits (`curl --max-filesize`), never executed or interpolated.
- [ ] **Portal/screen-share privacy**: password managers blacked out in
  shares and screenshots (kuwai privacy rules) — verify with a share.

## Phase 7: install, docs, story (target: Install 8, Docs 8)

- [ ] `install.sh` with `--dry-run`, a doctor (`kuwai doctor` + `rice
  doctor`), uninstall, and a backup of every file it replaces.
- [ ] A README with a 60 s video, the island states, the updater, the
  lock and login screens; a manual like Omarchy's (one page per area).
- [ ] Works on a second machine (no hard-coded paths, monitors or
  `$HOME/Projects`); a VM test.
- [ ] A name and a mascot-free identity: the island is the hook.

## Areas not to forget

- **Accessibility**: high-contrast theme, large text, every control
  reachable by keyboard and named for screen readers, reduced transparency.
- **Multi-monitor**: per-screen island style, which screen gets toasts,
  hot-plug while locked/asleep, mixed scales.
- **Laptop life**: battery health and charge limit, thermal state in the
  island (the 95 °C days), lid-closed docked mode.
- **Offline**: weather, rates, calendars cached; nothing errors loudly
  offline.
- **Localisation**: 24 h/12 h, date order, RTL text in notifications
  (works), non-Latin input in fields.
- **First run**: a short welcome that sets the essentials (bar, idle,
  wallpaper) instead of reading docs.
