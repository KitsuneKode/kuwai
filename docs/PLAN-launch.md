# kuwai + kittymux — road to a public launch

Written 2026-11-16 from: the three attached T3 threads (Product Security and
Quality Review, Visual Aesthetics Reference Research, Rice Cache and Package
Layout), `plans/README.md` + `plans/TODO.md`, `docs/PLAN-kuwai.md`, a fresh read
of Panacea (MIT, 45ddf2e), the earlier pocket-dots / t3code-bar studies
(`docs/research/2026-11-15-atmosphere-references.md`), the pstack Cursor plugin
(`~/.cursor/plugins/cache/cursor-public/pstack/<sha>/skills/`), and live
measurements on this machine (boot journal, PSS per program, unit states).

`docs/PLAN-kuwai.md` stays the running log. This file is the order of work.
The full list (notch interaction, panels, packages, media, kuwai-ui layers,
references, showcase) is [ROADMAP-showcase.md](ROADMAP-showcase.md).

---

## 0. The position in one paragraph

kuwai is ahead of every reference on the parts that are hard (glass, damped
motion, notch-as-attention, agents in the notch, polkit/lock/updates owned by
the shell). It is behind on the parts that make strangers adopt it: it installs
only on this machine (34 files lean on HyDE; the greeter hardcodes your two
monitors), the first 5 seconds after login look broken, boot costs ~4.8 GB, and
there is no scripted proof that a feature still works after a change. kittymux
is the portable product (any kitty, any WM) and should lead the launch; kuwai's
notch is the clip that makes people want it.

## 1. What is in flight (don't lose it)

| Where | What | State |
|---|---|---|
| `~/Depot/.t3/worktrees/rice/fix-quality-and-lifecyc-…` (`fix/quality-and-lifecycle`) | Codex's implementation of plans 001–010 slices: updater fail-closed + provenance + cache retention, greeter retry, idle-owner ack, session-scoped Clear, settings schema + atomic writer, privacy redaction until share-state known, fail-closed fallback lock, island geometry, DatePicker keys, Forget confirm, 200 % text, contrast, native test runner `bin/rice-ui-test` | **75 files, uncommitted, inactive.** 238 py / 148 bun / 196 QML / 3 Lua pass. Report: `docs/QUALITY-FIXES-2026-11-15.md` in that tree |
| main checkout, dirty | `rules.lua`, `LiveWallpaper.qml`, `Idle.qml` (live video out of the blur rule, coverage as a union, caffeine DPMS wake) + `ActionMenu/RaisedButton/Card/Theme` styling | uncommitted; overlaps the worktree on `Idle.qml`, `Theme.qml` |
| `~/Depot/.t3/worktrees/rice/t3-a463d3bc` (`t3/notch-usage-limits`) | old usage-limits branch | superseded (TODO says owner to remove) |
| `.worktrees/security-recovery` (`fix/security-recovery`) | old security branch | superseded; unexecuted tasks saved in `plans/2026-11-08-security-recovery-plan.md` |
| `~/Projects/kittymux` | sidebar rebuild (plan 015), `kittymux answer` | main clean at 83a1bd6 |
| live session | shell runs from the **dev checkout** (`KUWAI_ROOT=~/Projects/rice`), not `~/.local/share/kuwai` (stable) | the reload-leak notes say dev is the leaky channel |

No other Claude session is reachable right now; nothing else is running.

## 2. Your 12 issues — findings and fixes

### 1. Greeter brightness works "the wrong way" — root cause found
`greeter/keys` is a second, simpler brightness implementation:
- every key changes **every** screen (backlight + every DDC bus); the session's
  `bin/rice-brightness` changes only the focused screen (Super+Alt+F7 toggles all);
- DDC steps are `setvcp 10 +5` raw units, linear; the panel is `brightnessctl -e4`
  (exponential), so the two screens drift apart;
- `flock -n` drops DDC presses while a write is in flight, but the backlight never
  drops one: hold F8 and the laptop climbs 10 steps while the Acer climbs ~3;
- the HUD shows the last DDC bus written, or the panel, not the screen you're on.

Fix: ship `lib/brightness` into `/var/lib/kuwai-greeter` (greeter/sync) and make
`keys` call the same client with the focused monitor from the greeter's
`hyprctl monitors -j`; one HUD value per screen. One implementation, two callers.
Needs your `sudo greeter/sync` + one logout to verify.

### 2. Login: welcome → black → black → desktop
Measured this boot (journal, monotonic):
`23.18` password accepted → outro 1.1 s → `24.45` greeter Hyprland stops →
`25.61` greeter session closed → `25.62` your session opens → `27.23` your
Hyprland target up → shell paints later. So ~1.2 s of greeter teardown, ~1.6 s
of new compositor + modeset, then the wallpaper pops.

Causes we can act on:
- The outro ends by setting `locked = false` (GreeterView → black lock gone →
  Hyprland's black background) and only then launching. The welcome is cut, not
  faded. → End the outro on black (last 250 ms), so the cut is invisible.
- The greeter user runs its own pipewire/wireplumber/portals (journal shows
  `wireplumber[1215]` failing to write `/.local/state`); their teardown is part of
  the 1.2 s. → mask those user units for `greeter`.
- The session pops in. → Session's first frame is black; the shell fades the
  wallpaper in and grows the notch from nothing (a designed "boot reveal", ~400 ms),
  and no wallpaper daemon paints before the shell is ready.
- Two compositors means one real DRM handover; the Acer (10-bit, 200 Hz) may
  re-sync. That part can only be shortened, not removed. Prove it with the
  worktree's phase journal + a 240 fps phone video of both screens.

The worktree's report is right that the root cause isn't proven; the above is the
cheapest set that makes the gap read as one intended motion either way.

### 3. Boot RAM ~4.84 GB — where it goes (PSS, measured now)
| Program | MB | Note |
|---|---:|---|
| **voxtype daemon** | **3 123** | parakeet-unified-en-0.6b is 2.4 GB on disk, held in RAM (fp32, CPU) |
| kuwai shell (`qs`) | 469 | dev channel |
| Hyprland + Xwayland | 396 | |
| easyeffects | 125–194 | |
| docker + containerd + searxng container | ~300 | all at boot |
| shell-auth (`qs`) | 94 | |
| `rice-usage --watch` (node) | 85 | one websocket listener |
| nm-applet, hyde-config, kdeconnect portal | ~70 | HyDE leftovers |

No zombies, no orphaned rice helpers this boot (the pdeathsig + `rice-reap` work
held). `caffeine-mode.service` still fails every boot (needs interactive polkit;
kuwai owns caffeine itself) → disable it.
Biggest win by far: voxtype. Options in your fork, in order: int8 model (~4× less),
CUDA execution provider (moves it to VRAM), or load on first key-down and unload
after N idle minutes (voxtype already has an idle-unload knob for secondary
models). Then: docker/searxng socket-activated or on demand; drop nm-applet and
hyde-config; fold `rice-usage` into the shell (QtWebSockets) or run it under bun.

### 4. Inconsistencies (measured)
- Two brightness stacks (above). Two names: `rice-*` layers/bins/units vs
  `kuwai-*` (`kuwai-update`, `kuwai-wallpaper`, KUWAI_ROOT) — the one-pass rename
  is overdue. Token ratchet still sizes 61 / durations 89 / hex 69. Row/header
  styles still not one component (NotifsPanel/T3Panel/BluetoothPanel/clipboard).
  Live shell on dev while docs say stable. Greeter config hardcodes your monitors
  (`desc:California Institute…`, `desc:Acer XV272U`) instead of reading the
  user's `monitors.lua`.

### 5. Reimplementations to retire
| Hand-rolled | Use instead |
|---|---|
| `greeter/keys` brightness | `lib/brightness` (same as session) |
| `b64decode()` in ClipboardPanel | `Qt.atob()` |
| settings search by parsing `SettingsPanel.qml` | the worktree's settings schema (already done there) |
| `rice-update` keeping `src/ pkg/` forever (8.5 GB) | paru's `CleanAfter` policy; worktree implements retention |
| HyDE `wallpaper.sh` + HyDE colour modes (34 files) | a kuwai wallpaper/palette pipeline (awww + one colour tool), HyDE as an optional adapter |
| 5 services each with their own runner `Process` | one `services/Run` (already in the plan) |
| screen-scraped agent "waiting" for Claude/Codex | the agents' own hooks (see 7) |
Keep as owned (they *are* the product): notification daemon, polkit agent, lock,
island, updater review flow.

### 6. Implicit state machines
223 `Timer`s and 118 `Process`es in 186 QML files; the heaviest boolean clusters:
`Settings` 24, `Moments` 12, `IslandBar` 11, `ClipboardPanel` 9 (+ 6 sub-panel
`open` flags), `Notifs`/`NotifItem` 8 each, `Osd` 8, `Updates` 7. The machines that
matter, in risk order:
1. **Login handoff** (greeter locked → leaving → unlocked → launched / failed).
2. **Idle owner** (active → dim → lock → DPMS off; caffeine, dictation, saver, share).
3. **Island presentation** (rest → glance → full → moment → pulled → split capsules).
4. **Agent attention** (working → waiting → answered/denied → done → dismissed; per pane).
5. **Clipboard panel** (closed/browsing/searching/quicklook/editing/naming/menu/confirm/date/record/toast).
6. **Update run** (check → review → approve → build → install → restart-needed / failed / cancelled).
Each becomes one explicit `state` string with a transition function, a TLA+ model
via pstack's `statechart` skill (rules as invariants: "never two idle owners",
"a waiting agent's light never clears without an answer or the pane gone",
"no Allow is typed unless that prompt is on screen"), and each bug path replayed
as a bun test. Start with 1, 2, 4 — they're the ones with real-world harm.

### 7. kittymux × notch
Built: needs-you light, capsules, Agents panel, `kittymux answer allow|deny --expect`.
Next, in order:
1. **Hooks first, scraping second.** Claude Code's permission/notification hooks
   (and Codex's notify hook) can report "waiting" with the exact tool + command,
   and a permission hook can return the decision itself — no keystrokes typed into
   a pane. kittymux plan 005 already names this. Verify the current hook schema
   against Claude Code's docs before building; keep `answer --expect` as fallback
   for agents without hooks (agy, cursor-agent, opencode, gemini: unverified).
2. **Live Activities from panes:** a long command / test run / build in any kitty
   pane shows progress → ✓/✗ in the notch (kittymux already knows the pane and the
   exit); CI and PR review state for the branch the agent is on (`gh`).
3. **Overnight digest:** "while you were away: 4 agents finished, 1 waiting, 2 PRs
   green" as the welcome-back moment.
4. Account + reset on the limit capsule (waiting on kittymux `account`).

### 8. Security, portability, Apple-grade notch
- Security: land the worktree (fail-closed lock, privacy redaction, settings
  validation, updater provenance). `kittymux answer` stays opt-in, Allow/Deny only,
  Enter never Allow. Run the 18-item reconciliation it left.
- Portability: a clean-VM install is the gate (Arch first). Needs: HyDE optional,
  greeter monitors from the user's config, voxtype optional, NVIDIA paths optional.
- Notch ideas not built yet: Live Activities (above); a drop shelf (drag files onto
  the notch to stash / send to phone via the KDE Connect portal already running);
  mic/camera/screen-share privacy dots; matched-geometry flights (capsule → its row,
  toast → its centre row, unlock zoom); the boot reveal (issue 2).

### 9–10. Animation glitches and notch UX
I can't see these from code alone and the rules say no pointer/keyboard tests on
your session. Known open items: capsule pull and list swipes never tried with a real
pointer; eDP-1 stale frames under hybrid GPU. **Record each glitch** with
Super+Ctrl+Alt+Z (freeze note) or a 10 s clip and drop them in
`~/Pictures/kuwai-glitches/`; each becomes a feature-map entry with a test hook.

### 11. Clipboard
On open it selects the newest copy and scrolls to the start; ⌥← returns to where
you were. What feels weird is that ~15 independent flags decide the panel (see 6.5),
so overlays can stack, and editing is hidden: Quick Look already has an inline
editor (`QuickLook.editing`), but nothing tells you. Proposal:
- open on the newest copy **with its preview showing** (no extra key to read it);
- `E` or double-click edits in place in that preview; ⌘S/Enter saves as a new top
  entry and copies it (the original stays in history); Esc discards;
- one `mode` property replaces the flags, so only one overlay can be up.

### 12. Rice cache
Covered by plan 009 and implemented in the worktree (release `src/ pkg/` after a
good install, keep 3 archive sets, prune on cancel). Also: two bun caches
(`~/.cache/.bun` 3.7 GB on `/` and `Depot/.bun` 4.6 GB) → set one
`BUN_INSTALL_CACHE_DIR` on Depot; trusted list holds two uninstalled packages.

## 3. What to take from the references

**Panacea** (MIT, 247★ — the closest peer; code may be reused with attribution):
- Installer shape: per-step flags (`--no-sddm --no-grub --yes`), `*.bak-<time>`
  backups, `custom/` override dirs that updates never touch, an in-shell
  **Update** button with a **What's New** page (`WhatsNewView.qml`).
- Rebindable shortcut sheet (Super+/) that compiles to a generated binds file;
  settings pages with a live mock-up of the island.
- Small event sounds (connect, charge, screenshot, dictation start/done).
- An `AGENTS.md` + source map for coding agents working on the rice — fits
  "AI-native" and kuwai's own docs.
- Leave: the 7 600-line `shell.qml`, the bundled 300 unlicensed wallpapers,
  JetBrains Mono as UI face. Their Agents view is only usage bars; kuwai is ahead.

**t3code-bar** (MIT): alerts only on a status *change*; keep last-good data and say
offline / stale / revoked; contrast solved on the 8-bit value; hover previews that
wait 500 ms and drop the result if the pointer moved.

**pocket-dots** (GPL — ideas only): a wallpaper change as a short event on its own
layer (`sin(πt)` envelope, watchdog that really sets the new image); ink solved
against the actual crop; one layer namespace per surface, compositor animates only
what the app doesn't.

## 4. The verification system (pstack, adapted)

pstack ships the loop we need: `create-verification-skill`,
`maintain-verification-skill`, `statechart`, `maintain-formal-verification-skill`.
For kuwai:

1. **`verify-kuwai` skill** in `.claude/skills/` (symlinked to `.cursor/skills/`):
   - *Launch:* private harness first (`bin/rice-ui-test`, from the worktree: own
     namespace, offscreen, private HOME/D-Bus); live session only through
     `qs ipc … call test …` hooks.
   - *Doctor:* `rice doctor`, `islandbar-<screen> dump`, lock state `unlocked`.
   - *Drive:* test hooks only — `test peek`, `test moment`, `test card`,
     `test agentStates`, `test preview PANEL SCREEN`, `test settings N` — never
     pointer moves or typed text (your standing rules).
   - *Evidence:* grim per output + 60 fps clips + dump JSON into
     `~/.local/state/rice/verify/<run>/`, kept after cleanup.
   - *Feature map:* one file per surface — island, glance, capsules, agents panel,
     answer, clipboard, launcher, notifications, OSD/brightness, lock, greeter,
     updates, settings, wallpaper/saver.
2. **Statecharts** for the six machines in 2.6, in `tests/models/`, each invariant
   phrased as the user would say it, bug paths replayed as bun tests.
3. **Gate:** `rice promote` runs unit suites + the verify features whose files the
   diff touched; `maintain-verification-skill` weekly or after a big merge.
4. Install pstack in Claude Code too (`/plugin marketplace add cursor/plugins`,
   `/plugin install pstack@cursor-plugins`) so both harnesses share the loop.

## 5. Order of work

**Week 1 — land and stabilise**
1. Integrate `fix/quality-and-lifecycle` in reviewed slices on top of the dirty
   main edits (reconcile `Idle.qml`/`Theme.qml` by hand), commit, promote, run the
   live shell from stable again. Remove the two superseded worktrees.
2. Greeter brightness (issue 1) + login reveal (issue 2) — one logout to verify.
3. Boot budget: voxtype model choice (your call, your fork), disable
   `caffeine-mode.service`, docker/searxng on demand, drop HyDE leftovers.
4. Clipboard: preview-on-open, inline edit, one `mode`.

**Week 2 — proof**
5. `verify-kuwai` skill + feature map; statecharts for login, idle, agent attention.
6. Your glitch recordings → feature entries → fixes.

**Week 3 — portable**
7. HyDE optional (kuwai wallpaper/palette pipeline with the wallpaper event),
   greeter monitors from user config, installer with Panacea's flags/backups/custom
   dirs, Update + What's New in Settings. Clean Arch VM install/update/uninstall.

**Week 4 — launch**
8. kittymux hooks-first waiting + Live Activities.
9. Atmosphere: wallpaper set per the Wallhaven rule, retire the hacker greeter plate.
10. `kuwai demo` (fake agents in the notch, like `kittymux demo`) so anyone can
    try the notch without real agents.

## 6. Launch and the clips

Lead with **kittymux** (works for anyone on kitty), with the notch as the hero shot.

Shot list (10–20 s each, one idea per clip, no music needed):
1. "My notch asked me before Claude ran `rm -rf`" — agent waits → notch glows →
   Allow/Deny from the notch → the pane continues.
2. Six agents in kittymux, one key jumps to whichever is waiting.
3. Hold a key, speak, the text lands in Claude Code (voxtype ring).
4. Usage rings: "Claude resets in 1 h 12 m" across accounts.
5. Pull the notch down — rubber band, flick open.
6. Live Activity: `bun test` in a pane → ✓ in the notch.

Sequence: Show HN + X thread for kittymux (clip 1 + 2), r/unixporn for kuwai once
the atmosphere and installer land (clips 5 + wallpaper), Hyprland showcase after.
README for both: real screenshots from the verify harness, GIFs under 2.5 s.

## 7. Needs you
- `sudo greeter/sync` and one logout after the greeter fixes.
- voxtype: pick int8 / CUDA / lazy-load (it's your fork).
- `systemctl --user disable --now caffeine-mode.service`.
- Record the animation/notch glitches you've seen.
- OK to integrate the Codex worktree into `feat/assistant-agent` (or a new branch).

## 8. Update 2026-11-16 (later): motion/usability pass + reference scan

Branch `polish/fluid-motion` (worktree `.worktrees/fluid-motion`, commit d569f83,
not merged, not live). Built against Emil's standards (`review-animations`
STANDARDS.md), Fluid Functionalism's motion system, aiforui.dev/skills.

Done there:
- One gliding highlight per list (`FluidHighlight`) now also on the notch's
  notification list and tray menus; arrow keys make it jump (no glide on keys);
  it fades with a row being swiped; its ring is FocusRing's look (it was accent
  blue while every other ring is soft white). Bugs fixed on the way: the notch
  list lit row 0 on open and kept the last-pointed row lit after the pointer
  left; the Agents panel drew two rings on the keyboard row.
- Motion review: padlock/swell overshoot 1.8–2.4 → 1.2–1.4; lock-card snap-back
  without overshoot; StatRing 400 ms → glideMs; Farewell ease-in → ease-in-out.
  Kept on purpose: the peak-hold fall (gravity) and the 14 s lock dim.
- Clipboard: ⌃S keeps a Quick Look edit as the newest copy (panel stays open,
  lands on it); double-click the text to edit; the footer says both.
- `greeter/keys`: brightness on the focused screen only (issue 1).
Verified: qmllint clean on all 10 files, offscreen load test passes, 77 bun tests,
6/10 files compiled through the live `test compile` hook (the other 4 can't be
compiled across trees: same-folder types don't resolve; they compile at promote).
Not yet seen on screen.

New from the references:
- **Panacea answers agent permission prompts through the agents' own hooks**
  (`PermissionRequest`, Claude Code and Codex): a notification with Allow/Deny,
  offered only when the whole command is one line it can show in full (≤75
  chars), the original prompt left alone if the card is ignored or the agent's
  pane is focused. kuwai is already the notification daemon, so this is a small
  `bin/` hook script + the existing notification actions. It replaces typing into
  panes for Claude/Codex; installing hooks edits ~/.claude and ~/.codex settings,
  so it needs your yes.
- t3code-bar: secrets in the system keyring (Secret Service), `Debug` redacts
  tokens, a strict CSP. kuwai's `t3-token` is a mode-600 file with read-only scope
  (acceptable; keyring is the upgrade).
- Panacea `FocusGrabber`: retry focus each frame for up to 30 tries because a new
  layer gets the keyboard a frame late (first keys lost). Worth checking against
  kuwai's launcher/clipboard first-keystroke behaviour.
- Remaining motion findings, owned by the quality worktree's files: Overview's
  keyboard selection scales 1.05 (keys shouldn't animate; 1.02 max for hover).
