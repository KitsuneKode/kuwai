# kuwai — working plan (kept across sessions)

Written 2026-11-01 so the plan survives context compaction. Tick items here as
they land. User wants: extremely secure, premium, tasteful, fast, Apple-grade.

**2026-11-16: the order of work toward a public launch is in [PLAN-launch.md](PLAN-launch.md)** (in-flight worktrees, the 12 reported issues, references, pstack verification, clips).

## STATE (2026-11-27, late) — what is left, where UX falls short

Done today, beyond the release review: wallpaper changes at a measured steady
60 fps (crop, even motion, transparent fades, awww swapped under the cover,
recolour after); live wallpapers through the same reveal (frozen frame →
first frame), 10-bit HEVC loops, thumbnails never block the Live tab; rapid
steps coalesce (newest apply only, intent-based stepping, presses take turns);
the 13 GB OOM (two BiRefNet cut-outs) capped for good; two audits fixed
(Fable: leaks/security; Neon: rendering/long-session); limited agents say
"Limited · back in" instead of a ✓; clearer state marks; Kiro in kittymux
(PR #61); a muted mic says so at the dictation key (shuush 0dc1ce2).

Left, in order:
- [ ] Warm mic + pre-roll, queued dictations (fork, feat/warm-mic-queue).
- [x] Screensaver as a real idle step (saver → fade → lock; still default). c4c8d05
- [x] README screenshots from healthy rehearsal scenes (7bf600d). Clips as 1:1 crops: the owner runs the recording brief while away.
- [ ] Fresh-VM pass: install, first login, lock, suspend/resume, greeter, uninstall.
- [ ] Root never runs checkout code; signed release (needs the owner's key).
- [ ] The shell's 99 % / 853 MB episode (17:18–20:35) is unexplained. The
      repo's quickshell (built against Qt 6.12.0, running on 6.12.1) is a weak
      suspect: a patch release keeps Qt's private symbols. Stay on extra's
      quickshell (never quickshell-git); catch the next episode with a stack.

Where the experience is still thin:
- Feedback when something silently can't happen: a muted mic (fixed), no
  model loaded, a provider out of quota mid-dictation, wallpaper apply failing.
  Every such case should say one plain sentence where you are looking.
- The island's agent states now read well; the panel rows still need the same
  marks and a reset time for T3 limits (T3 gives none yet).
- Theme switches through HyDE take seconds; the picture changes at once but
  the colours land later. A batched recolour (one Theme change) would hide it.

What Hex taught (MIT, ideas only): protect code/links/paths/vocabulary from
cleanup rules (done); route by app and by browser site (done); keep a cancelled
take (done); restore the clipboard only if it is still ours, richest type
(done, off by default); warm mic with pre-roll and queued delivery (in
progress); per-entry re-clean and spoken commands ("my clipboard", "rewrite
this") next; real words-per-minute from history.

## RELEASE REVIEW (2026-11-27, night) — Astra 6.2, Grok 4.7 xhigh, Neon 4 high, Fable 5.2

Verdict of all four: not ready to announce yet; nothing is a cross-user or root
break in normal use. A `v0.1.0` tag is already public (2026-11-25, `778c67c`,
unsigned, 139 commits behind): never move it. The presentable release is a
signed **v0.2.0** cut after the "Blocks the release" list below and one
fresh-VM pass (install, first login, lock, suspend/resume, greeter, uninstall).

Landed tonight: PAM answers only the prompt it asked (a code or PIN prompt is
shown, never handed the password); fingerprint through PAM (no side channel);
lockout countdown on lock and login; kuwai-sleepguard (sleep waits for a
confirmed lock, re-held on wake); the failure unit relocks with hyprlock;
triage keeps real news and can't be spoofed by a level hint; history reload
looser rule fixed; lock art local/cached only; a hidden lock card shows no
status or picture; Night Shift single request; ssh/gpg agents and portals never
ended; clipboard and feeds strictly opt-in (login, units, rescue, consent
errors) with "history is off · Turn on"; kitty and the freedesktop sounds in
core; installer stops on a failed backup; greeter rests on the desktop
wallpaper, 2× clock clamp; AMD GPU named AMD, CPU core temp no longer the GPU's;
fleeting updates never overwrite a kept card; Warmth handle, Settings icons,
"replaced by" row, TB sizes, confirmations disarm and Stop binds to its start
time; qt/ssh env guarded, any AC name, VA-API guard; screenshot/OCR say what to
install; launcher hides absent tools; Qt JS lint (object spread broke the login
screen once); portal.frag openings (unlock doors, login iris, saver veil);
kuwai secrets; docs and site rewritten for strangers (Neon, merged).

Blocks the release:
- [ ] Release provenance (Astra P0): kuwai-setup verifies a signed tag in a clean
      staging dir before running anything; README installs the same artifact.
- [ ] Root never runs checkout code (Astra P0): system/session, system/install,
      greeter staging and the update helper install from a verified release, not
      the user's clone.
- [ ] Fresh install themes (Neon P0): `kuwai-look list` includes the downloaded
      Kuwai Night wallpaper; theme cards have thumbnails or say "downloads on
      first use"; applying a theme keeps Colours on Theme; drop or credit the
      10 unlicensed wallhaven sets; the default wallpaper gets a digest (Grok).
- [ ] README media (Fable P0): re-shoot tour images from healthy scenes (no
      error notice, no red CPU, the new Now Playing); clips at 1:1 crops;
      login/lock/goodbye media current or cut.
- [ ] Update prompt binds to one transaction (Astra P1); greeter --undo needs a
      root-owned receipt (Astra P1); a failed forward-rollback migration returns
      failure before activation (Astra P1).
- [ ] Relocated XDG dirs keep the assistant's denied paths (Astra P1).
- [ ] Display presets work with an empty monitors.lua (Neon P0); a desktop's
      first monitor gets workspaces 1–10, two identical monitors don't collide.

Before announcing (P1/P2):
- [ ] Key caps say Super/Ctrl/Alt on PC keyboards (Fable); Welcome copy and 2×.
- [ ] One spelling (UK or US) and one brand casing; CHANGELOG has one 0.2.0.
- [ ] Usage/Updates/Agents/Cleanup: one state each (Fable 13–15); orange only
      for "needs you"; lock and login share one token set (Fable 12); farewell
      marks all drawn as Shapes (Fable 11).
- [ ] AUR updates with yay or no helper (Neon); kittymux path from PATH.
- [ ] Cache clear via O_NOFOLLOW/fwalk (Grok P2); ports pid from /proc, not ss
      text (Grok P2); Agents Stop can force and says "on this network".
- [x] Voxtype: clear stale cancelled takes at daemon start (Astra P2).
- [ ] Rehearsal scenes for Clipboard, Lock, Greeter, Assistant, Osd, Popups.

## VISUALS + HEX PASS (2026-11-27, evening) — six reviews

Reviews: Grok 4.7 (lock/login), Composer 2.5 (screensavers), Neon 4 medium
(wallpapers, live), Sonnet 5.5 (the whole visual journey), Sol 6.2 (cost and
correctness), Neon 4 high (Hex for voxtype/shuush; Hex is MIT).
Landed: README clips (docs/media/clips, recorded live on an empty workspace,
nothing personal); greeter plain error + 8 s launch timeout; lock hides a hidden
message's title, lock art only from the local cache; theme pins sha1:/sha256: +
a named User-Agent; live-wallpaper GPU decode on AMD/NVIDIA; wallpaper change
'Lines' (Sobel contour, no model); lock keeps colour (saturation 0.55); Still
saver settles; shuush: browser site → profile by title, rules never touch
code/links/paths/vocabulary.

Next, by severity then value:
- [x] P1 lock: logind suspend releases its inhibitor only on a confirmed lock and
      reacquires on PrepareForSleep(false) (Sol 1); a crash while locked always
      has a locker (marker written before the lock; standalone locker in the
      failure unit) (Sol 2).
- [x] P1 login: first PAM question may not be the password (fingerprint): show
      the real prompt, submit only to a password prompt (Grok 1); lockout
      countdown on the lock (faillock, from shell-auth) (Grok 2).
- [ ] Lock: a sampled plate behind media and notifications (Grok 3); next event
      on the lock, title only under the privacy rule (Grok 4); dismissing a
      hidden or code notification needs an unlock (Grok 5).
- [ ] One ClockFace for lock, login and saver (Sonnet 3); login ClockGround zone.
- [ ] Saver as a real idle step: saver → fade → lock, default Still with the
      current wallpaper (Sonnet 4); long-idle ladder: after an hour, clock on
      black or DPMS (Composer 1); photo shuffle (Composer 2); one throttled GLSL
      style (Composer 3); a quiet media pulse (Composer 5).
- [ ] Live wallpaper: Qt fallback obeys the 10 s release (Sol 4); per-connector
      mpvpaper ops serialized, success only when playing (Sol 5); DPMS state from
      the compositor (Sol 6); a still frame under a paused live wallpaper (Neon).
- [ ] Wallpapers: replace or mark the 11 unlicensed theme sets (Neon; Sonnet's
      per-theme picks); wallcheck --default gate in tests; 'Get more' packs with
      pins; day/night variants via K.sun_hours; per-monitor wallpapers.
- [ ] WallFx: fixed participant set, abandon on hotplug or a decode error,
      canonical path match (Sol 11); picture and accent land together (Sonnet 7).
- [ ] Voxtype (Hex): multi-MIME clipboard snapshot + restore only if unchanged;
      adaptive release tail + warm mic with pre-roll; queued dictations with
      ordered delivery; per-entry audio + 'Re-clean' in Studio; 'my clipboard' /
      'rewrite this' / 'stop dictation' phrases; usage rollup with real WPM.
- [ ] Earlier: Activity tab; Docker/journald in Caches. (API keys → keyring: done, kuwai secrets.)
- [ ] Boot: a minimal Plymouth theme (black, one accent ring) (Sonnet 8).

## INSPIRATION PASS (2026-11-27) — Clove and pocket-dots, with Neon 4 and Sol 6.2

Landed: Night Shift's switch starts hyprsunset itself; the focused border at half
accent; a fresh install gets Kuwai Night's wallpaper; dictation's ring is one shader
(voice ripples from the island while listening, accent comets while writing);
cancelled takes kept 10 min in RAM and brought back with Super+Ctrl+Alt+D
(voxtype fork 3b53a49f, `voxtype record recover`); Cleanup → Caches (disk dots,
comes back / check first, each tool's own clean); dev servers with name, agent,
age and a verified Stop; the launcher never ends session processes and says when
one is still running; cards' top-edge light; Geist Mono fallback; no wallmap job
without the model.

Next, in order (both reviews agree):
- [x] Activity tab in System: apps grouped by systemd scope (app-*.scope) with
      desktop icons, CPU per logical CPU from cgroup cpu.stat deltas while open,
      PSS on a slower beat, Stop/Force quit through kuwai-procs. Done: bin/kuwai-activity
      (1 s frames, PSS every 5 s, only while the tab is open), kuwai-procs --end-unit,
      services/Activity.qml + activity.mjs, modules/island/ActivityView.qml; scenes
      system/activity-*. Not done: opening System straight on the tab from the CLI.
- [x] API keys in shell rc files → Secret Service: scan named files only (name,
      file:line, never the value), store via secret-tool on stdin, verify, then
      rewrite atomically; a per-tool launcher loads it. Never print or log a value.
- [ ] Caches: Docker images and journald as "check first" with their commands.
- [ ] Wallpaper: a zero-model contour reveal (Sobel edges sketch in, then fill).
- [ ] README clips: record from the rehearsal (Xvfb) or on the live session while
      the owner is away (they agreed to recording; not while they type).
Not taken: Clove's dotted canvas behind cards, Geist Sans, continuous Orbit/Ripple
indicators on the resting notch, pocket-dots' pixel colonies and opaque bar.
Clove is a paid product: ideas only, never its code, images or words; pocket-dots
is GPL-3.0 with separately licensed assets: ideas only (AGENTS.md).

## FINAL REVIEW (2026-11-27) — five models at d0caa60, plus the owner's reports

Threads: Grok 4.7 (attacker as you), Sol 6.2 (data/runtime), Astra 6.2 (privileged
paths, install), Gemini 4 Neon (features x matrix, voxtype/shuush), Fable 5.2 (design).
Done: greeter home group (Astra 1, 6645c84); everything ticked below landed by 15614aa
(P0 d55aa5c 32220b2; security 70e552d 0ab421b c2b77c1; install b5ae061; runtime baac617;
design 2ef43f8..15614aa; voxtype fork bb8aebb4; shuush 54c95b3 a817adc a8caa41).

P0, broken for the owner now:
- [x] voxtype paste_over_chars never runs: streaming post-process returns before it (Gemini C1; fork daemon.rs stream_post_process).
- [x] paste restore races shuush's PP_KEEP_ON_CLIPBOARD wl-copy; restore keeps one MIME and drops x-kde-passwordManagerHint (Gemini C2).
- [x] closing Wi-Fi/Controls in minimal mode leaves the notch full width (owner).
- [x] reminders, alarms, pomodoro, timers in the notch "not working" (owner): check end to end.
- [x] alarms due together: only the last rings, the rest vanish (Sol 2); timers that end during a restart are dropped (Sol 7).
- [x] swipe up closes the Controls/Wi-Fi and notification panels, like the island (owner).
P1 security:
- [x] update helper: one pkexec per operation, op in argv, exit after it; -Syu once; refuse .pacnew on passwd/shadow/group/gshadow/fstab/crypttab (Grok 1, Astra 4/5/11).
- [x] root installs from a writable tree (install-helper, system/install, greeter/install, auth pin; wake unit hardening) (Grok 2, Astra 2/3): install from signed-tag blobs, digest in the prompt.
- [~] kuwai-auth.service loads user shell-auth when unpinned; drop-ins (Grok 3). Accepted, see below.
- [x] authWords: require /usr/bin/qs, the pinned path, the kuwai-auth cgroup (Grok 4).
- [x] x-kuwai-crash hint from any sender briefs the assistant (Grok 8).
- [x] assistant: request file swappable; read → sandbox script → network (Grok 5).
- [~] VoxtypeHost loads QML from XDG_DATA_HOME into the shell (Grok 6, plan S4). Accepted, see below.
- [x] update-self: signers from the current commit only; KUWAI_UPDATE_REF unsigned (Grok 7).
- [x] greeter/start /tmp fallback; extend the lint to greeter/ and system/ (Grok 10).
- [x] PAM multi-challenge (password + OTP) on greeter and lock (Astra 9).
P1 runtime and install:
- [x] idle dim / pre-lock fade stick when an inhibitor engages (Gemini 4).
- [x] screen-share privacy resets on a config reload mid-share (Gemini 3).
- [x] a panel/Center open on an unplugged monitor strands state (Gemini 5).
- [x] Dim forgets a missing monitor's level (Sol 3); OTP history misses (Sol 4); T3 answer dies with the panel (Sol 5);
      volume keys without a player wake the saver, forced latch after fullscreen (Sol 9, Gemini 19); calendar TZID (Sol 10);
      Limits "partly out" (Sol 11); FluidHighlight brightens on loss (Sol 12); keys.tsv lost edit (Sol 8).
- [x] rollback migrations order (Astra 6); kuwai-home reinstall drops a replaced config (Astra 7); migration 0006 consent (Astra 8);
      wallpaper link blocks migration 0005 (Astra 10); two users share the root log (Astra 12); greeter undo with greetd (Astra 13);
      dev channel root outside ~/Projects (Astra 14); session restore umask (Gemini 21).
P1 voxtype/shuush quality:
- [x] long takes: budgets and max_tokens scale with length; `break` -> `continue` on a rejected provider (Gemini 6).
- [x] gate mangles "first/second" lists, "bullet", >10 items, negated self-corrections (Gemini 7).
- [x] drop-term/float-term get Ctrl+V, not Ctrl+Shift+V (kuwai-clip, fork active_window) (Gemini 8).
- [ ] cancelled take: keep the last one in RAM, restore key (owner, proposal).
P1 design (Fable):
- [x] Cleanup: size from the ceiling, pin the action row, Mark all + Ctrl+A, scenes (1, 2).
- [x] section tabs move between 460/640 panels (3); stage section panels in the strip (4).
- [x] one key notation; Welcome says ⌘ is Super (5); Welcome steals focus (Gemini 14).
- [x] Usage: header, chip and forecast agree; provider trouble as one pinned line (6, 7).
- [x] one error primitive (Ui.Notice + Retry) (8); EmptyState everywhere (9); Now Playing centred on play (10); copy (12, 13).
- [x] 2x text: lock, Settings sidebar, Wi-Fi rows, Island chrome, Theme, Updates grid (Gemini 9).
P2 small:
- [x] Launcher Controls/Wi-Fi text and action, ⌥1–3 in notch mode (Gemini 16); iwd glyph (17); Island.toggle routing (18);
      weather location refresh (20); reduced-motion latch (11); HyDE terminal button (12); VoxtypeHost focusedMonitor (13);
      Shortcuts page: non-Latin, Lock ⌫, ↑↓ in search, F9 (15); Theme colours on Live (22); F9 release tail (23);
      Sound mute "M"; Shortcuts "[Utilities]" prefix; Usage tooltip over tabs; Sound strips mismatched; Displays "Reading…" forever (Gemini 10).

Accepted risks (same user, no new boundary):
- VoxtypeHost loads voxtype's QML from XDG_DATA_HOME into the shell (Grok 6). The shell
  itself runs from files that user can write; the password prompt is a separate pinned
  process (kuwai auth pin) whose window the island trusts only from /usr/bin/qs, the
  pinned or stable shell-auth path and the kuwai-auth.service cgroup (authWords.isPrompt).
- kuwai-auth.service is a user unit, so that user can change it or add drop-ins (Grok 3).
  Same mitigation: the prompt pinned under /usr/local by root, and isPrompt above.
Left: cancelled-take recovery (proposal only, the owner's call); a VM first login and the
README clips (both need the owner).

## REVIEW (2026-11-26, night) — six models, what is fixed and what is left

Reviews (read-only): GPT-6.2 Astra (privileged paths), GPT-6.2 Sol (data and
runtime), Opus 5.5 (architecture, launch), Fable 5.2 (design, island), Grok 4.7
(attacker as you), Gemini 4 Neon (features, voxtype). Fixed: 6c17030, c7ec6b5.

Left, needs a decision or the owner:
1. Signed releases (Opus): done 2026-11-27. The owner's SSH key is in
   `release-signers`; `kuwai release vX.Y.Z` signs, update-self refuses anything
   else. Left: a passphrase on ~/.ssh/kuwai_release, and the first signed tag.
2. Root installs from folders you can write (Astra, Opus, Gemini, Grok):
   `kuwai update install-helper`, `kuwai auth pin`, `system/install`, greeter
   `--undo` from a legacy backup. Real fix: install from a signed tag's blobs
   (after 1) or a root-owned package; show the helper's sha256 in the prompt.
3. The root update session (Gemini, Grok): one prompt opens four hours of any
   op; put the op and package list in pkexec's argv; split -Sy/-Su into one
   -Syu; refuse `.pacnew` take on passwd/shadow/group/fstab/crypttab.
4. voxtype: VoxtypeHost loads voxtype's QML into the shell (Gemini S4);
   voxtype.lua's suppress submap has no timeout and paths aren't quoted (S6).

Left, agent work: the remaining /tmp fallbacks in shell/ and greeter/ plus a
lint over them (Fable, Gemini); notification history keeps OTPs and its dir
isn't 0700 (Sol, Grok); auth-summon/auth-pending can be spoofed (Grok);
paste can land in another window (Sol); two T3 approvals share one process
(Sol); the island's design list (Fable): keyboard section switches crossfade,
a panel swap fades on two clocks, two drag handlers on the peek, Now Playing's
transport rebuilt on each play/pause, glance panels close under a reader,
DND and Night Shift share a glyph, ControlTile at 200 %.

## NEXT (2026-11-26, evening) — what is left, in order

Done today and live: new AUR packages install through the review (c329b4b), the
password prompt's accent (418af39), Devin/Cursor not "working" when only opened
(e281031), holds and the package browser (c7b5fc0, its own thread), shortcuts you can change, plain F-keys, one agent
identity, the screensaver's black start and the Dusk flash on exit, dim at
3 min to the floor (panel 1, monitor 0), the Esc and right-click pass, apps
holding the screen on (org.freedesktop.ScreenSaver: bin/kuwai-inhibit), the
rehearsal's Usage flake (its stand-in helper died after 10 minutes). The
providers/budget/recap work landed from its own thread (ab9d974).

Needs the owner (minutes each). Done 2026-11-27: `kuwai auth pin`, `kuwai update
install-helper`, `sudo greeter/install --code`, the USB-mic udev rule, the release key,
kittymux #47 #49 #59 #60 merged.
0. Quickshell: Arch's package is still built against Qt 6.12.0 (the system has 6.12.1);
   wait for Arch's rebuild (pacman -Si quickshell: a new pkgrel) or build it from Arch's
   own recipe (gitlab.archlinux.org/archlinux/packaging/packages/quickshell, makepkg -si).
1. One logout: the login handoff, never yet seen.
2. voxtype's video memory (3.4 GB of 6, the root of every failed video
   allocation): pick a step in the fork (arena that grows by what's asked,
   unload after 15 idle minutes, fp16). Agent work once chosen.
3. Look once at the gliding list highlight (Wi-Fi, Bluetooth, Sound, the launcher)
   and the dictation ring's voice glow and writing light.
4. Look once at what was only ever rehearsed: Settings → Shortcuts (change a
   key), the saver starting and ending, F-keys Plain.

Agent work, best value first:
1. A launch-blocker pass: install.sh on a clean container end to end (CI's
   cleanroom covers the repo; a first login has never run anywhere fresh).
2. Statecharts for login, idle and agent attention (PLAN-launch §4): the
   idle chain alone has caffeine, dictation, saver, share and app holds now.
3. Screensaver: the next calendar event; media keys that act without waking it.
4. kittymux: Live Activities (a build in a pane → ✓ in the notch), hooks first.
5. Launch assets: README with clips (PLAN-launch §6).

Outside kuwai, seen in the logs: kittymux's sidebar-kit test runs abort in
cairo at exit (15 kitty cores a day); kitsunesnipe's install.ps1 tests write
~10k PowerShell warnings a day to the journal.

## STATUS (2026-11-26) — shortcuts you can change, plain F-keys, one agent identity

Landed and live (stable d1ff63a, then the row polish): Settings → Shortcuts
rebinds any kuwai action (a key-free submap so the chord reaches the panel;
conflicts named, Replace moves a chord off another action; ~/.config/kuwai/keys.tsv,
`kuwai keys`, hypr/kuwai/keys.lua applies it live after user.lua). Keyboard →
Function keys: F7/F8/F10 kuwai's (default) or plain (settings fKeys). Agents:
one canonical key per session (kitty pane, T3 thread, hook session) in
agents.mjs `sessions`; every surface reads Agents.sessions / Agents.tally
(tests/shell/agents-identity.test.mjs). Proven live: a rebind and its reset,
plain F-keys on and off (hyprctl binds), the agents tally over IPC.
Not proven: a chord pressed into the panel on the live session (no synthetic
input); the capture submap's 30 s self-reset.

## STATUS (2026-11-21, later) — the shell is a systemd service (feat/shell-unit)

Why it felt flaky: the shell had no keeper. 09:36 crash → Quickshell's handler
re-exec'd it as ~/.config/quickshell (a prototype) with the old run's helpers
attached; 10:11 `killall qs` → no shell, and kuwai-auth used up 3 tries in
60 s with no fallback installed (no password prompts). Now kuwai-shell.service
(Restart=always, cgroup kill, crash handler off) + kuwai-shell-broken.service
(Waybar + notice until the next save); bin/kuwai-shell is the client; apps the
shell opens go to app.slice via Apps.qml; auth never gives up (backoff to
30 s); migration 0003 links the units; `kuwai status`. The CPU gate's coin
flip while agents work is named (10 %), not hidden.

Live (stable, 2026-11-21 ~11:00): promoted through `kuwai promote`; the
comment-removal session's work committed first (7e665f8) at the owner's word.
Proven on the session: SIGKILL of the shell → back in 1.1 s, notifications
its own, no dunst, kuwai-check green incl. "unit: kept running by
kuwai-shell.service"; the launch command runs in app.slice with Hyprland's
environment and nothing in the journal. Found on the way and fixed: the unit
lacked what hl.env sets (bin/kuwai-session-env now exports Hyprland's whole
environment, uwsm-style, minus HYPRLAND_CONFIG); a restart's own SIGKILL
fired OnFailure and the fallback cancelled the start (SuccessExitStatus).
Not proven: a real login (startup.lua's export + first start), a broken file
reaching the fallback unit on the live session.

Next: the T3 ring's 600 ms step costs ~120 frames on the 200 Hz monitor (8–12 %
in a second that has one): step it cheaper or less often; the notification
centre (badge 7, list empty; clicked items linger; smart cleanup) from the
last thread; HyDE pieces still running here (awww, wallpaper.sh,
hyde-config.service, dunst, Waybar).

## STATUS (2026-11-21) — five lists and the owner's reports, landed on feat/assistant-agent

Landed (each its own commit; `git log 2026-11-20..`): keyboard and mouse reach
the same things everywhere (Ctrl+Tab, lock and login focus, island cards on
Super+Ctrl+↵); nothing repaints at rest (ghost snapshot, minute clocks, rings
step only while seen); one screensaver film on all screens; one ContextMenu,
one Button (PillButton gone), one ListRow for T3/Agents/Notifications/Launcher;
contrast ≥ 4.5 and every panel whole at 200% text (rehearsal known list: 0);
weather finds its own place; voice HUDs kept across a monitor's deep sleep;
kuwai-check runs the live checks itself. From the owner's reports: the lock
no longer restarts the shell when a monitor comes back (the "lock screen
died" flash, the crash screen after sleep); screens stay on while agents work
(turning them off unplugged DP-3 and moved its workspaces); closing the
notification centre crashed the shell (ScrollFade switched a list's layer
inside Qt's own teardown; b7f56bc), and the restart came up on
~/.config/quickshell, an old prototype (QS_CONFIG_PATH now; 90e9a9f); icons
looked up once and cached (the 11-20 QIconLoader crash). Usage: spend
per provider from the local logs (bin/kuwai-spend). The T3 capsule says what
it wants in a word. promote asks Landlock first; install.sh tried on a fresh
Arch container (font package, no session bus, uninstall without python).

Needs the owner: `sudo greeter/install --code`, then one logout (the new
handoff; the greeter's Hyprland crashed at handoff on 11-19 and 11-20);
`hyprctl reload` or a new login for Super+Ctrl+↵; the monitor's own "DP deep
sleep" off; a `diagnostics:read` T3 token for spend from T3 itself
([PLAN-agents.md](PLAN-agents.md)).

Not proven: the 11-20 QIconLoader crash is mitigated, not reproduced; a real DPMS
cycle on the live session; the 11-19 18:22 poweroff (systemctl, from the user
manager) has no cause found. Next: [PLAN-agents.md](PLAN-agents.md).

## STATUS (2026-11-17, night) — audit pass 2, promoted (stable d47301e)

Landed and live: one-time codes by rule (services/otp.mjs: the origin-bound
"@host #code" line first, then a code phrase beside the number; 8 of 54 false
positives → 0) and feed severity from the feed; clipboard as one overlay mode
with ⌃Z after a delete (clipstate.mjs); "Cleared N · Undo" for notifications
(notifUndo.mjs; one Theme.undoMs for both); one System panel ("vitals" is an
alias; switches always in the panel, GPUs side by side); theme picker opens on
a kept listing; at rest 7 helpers instead of 11 (render server on demand,
brightness OSD on the controller's socket, Shazam/T3/crash/network by events,
kuwai-usage under bun) and kuwai-notify delivers again (it had failed on every
call without -A since 11-05); dates through config/Dates (locale order, week
start, 12-hour clocks read 9:05); Inter as the face anyone can install, SF Pro
when present; the login screen reads monitors and keyboard from validated data
(home/.config/kuwai-greeter.conf); JSDoc types checked by tsc in CI.

Not seen by a person yet: Super+V (mode, undo), Clear → Undo in the centre,
the login screen with the new config (next login; `sudo greeter/install --code`
still pending), Inter on a machine without SF Pro.

Next: Accessible names on the other ~100 pointer targets; strings through
qsTr ("Today/Yesterday" are still English); exact-shape blur
(BackgroundEffect); tokens to zero and the rice → kuwai rename; HyDE optional
+ clean-VM install + migrations; Hyprland profile (needs perf); memory:
Clipboard.renders, OllamaService.htmlCache/sessions bounds, and whether the
overnight creep changed with the polls gone (read memlog tomorrow).

## STATUS (2026-11-17) — audit pass 1, committed a27e6e2 · 7af2916 · 2797cb9

Done and checked (246 py / 159 bun / Lua pass, kuwai-check green, panels seen):
plain text on every outside string (103 `Text`, lint in tests/security);
streaming answers can't fetch (Turn.liveMarkdown); links are web/mail only;
login screen code is root's (greeter/install, `--code`, a real `--undo`);
state folders 0700; CI runs every Bun suite, bunfig scopes `bun test`;
clipboard ⌃⇧⌫ / ⇧⌦ / ⌃X ignore key repeat; capsule count on the wordmark's
baseline; one date order; settings rows without the provenance line; dock
names on two lines; no MAC-named Bluetooth rows; Media empty state; calendar
hint is an action; four panel widths (Theme.panelS/M/L/XL); night_light off by
default; kuwai-check knows dictation; AGENTS.md.

Needs the owner: `sudo greeter/install --code` + one logout; SSH key
passphrases and `chmod 700 ~/.ssh ~/.codex`; voxtype fork (its OSD repaints a
whole screen while dictating: 25 % of a core; a playback stream held open at
44.1 kHz; the model held in 3.4 GB of VRAM); delete /etc/pipewire/pipewire.conf;
zram ~12 GB; encrypted swap; disable caffeine-mode.service.

Next, in order: (1) clipboard as one `mode` + undo for delete; undo for
notifications Clear all; (2) one System panel (system + vitals); (3) memory
drift + helpers (node usage watcher, render server on demand, shazam loop);
(4) profile Hyprland (14–30 % of a core while agents stream); (5) Accessible
names on the other ~100 pointer targets; (6) dates through the locale, strings
through qsTr; (7) exact-shape blur (BackgroundEffect); (8) HyDE optional,
greeter monitors/keyboard from the user's config, clean-VM install, migrations;
(9) tokens to zero and the rice → kuwai rename; (10) a font that can be shipped
(Inter/Geist) with SF Pro optional.

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

## DONE 2026-11-07 (night)
Read & Reply panel (whole email, composer, Ctrl+Enter); email text keeps its
shape; usage cards by account (Session, then Weekly) with edge fade; hover
ring pairs per account (session outer, weekly inner) taking turns; T3 folds
while music owns the sides; no T3 mark over moments; rim follows the corners;
Settings scrolls and Tab walks controls; promote auto-rollback (4 s);
Wellbeing (breaks, bedtime) with settings; pomodoro colours and round dots;
welcome back by time of day after hours; swipe to clear on the lock screen.

## STATUS (2026-11-07 afternoon)

Done since the morning: one Copied with preview; T3/kittymux/assistant
"done" in the island only (toasts when the island is covered); Gmail
threads and GitHub conversations in the reader, two-step pull; rim follows
the ears; Segmented pill (lookup ran before segments existed); filter row
aligned; Super+Ctrl+N blanks the other screen (curtain + backlight 0);
jack: one card, mic first, replug not lost; charge-limit only after a seen
charge; paused music → pause mark, off the notch after 10 min; focus: new
windows get the keyboard over the assistant/clipboard, hover previews no
longer take it; assistant turns belong to their chat (no lost answers),
background ring/unread dot, pull the green notch to open, near-full-screen
size, notch-shaped frame, offline state; ~/.agents/skills matched per
request; usage rings centred; usage rows as a 20-segment bucket.

Memory: Process/FileView re-runs ruled out (isolated qs, 1000+ runs flat).
Measuring JS heap vs Pss_Anon (KUWAI_SHELL_ENV="QV4_MM_STATS=1
QT_LOGGING_RULES=qt.qml.gc.*=true") to tell JS from native growth.

## STATUS (2026-11-07 morning)

Found and fixed: every shell restart orphaned its streaming helpers (pactl
subscribe, udevadm monitor, the brightness watch, the Shazam 1 s poll loop):
127 processes + 78 loops, ~1.1 GB. Now setpriv --pdeathsig, and promote
refuses a streaming helper without it. Old orphans need one manual kill
(the session's classifier won't let the agent do it).
Dim: one service (services/Dim.qml), relative (40 %, at most 15 %), monitors
too, restore read back and retried. Live-tested 15→6→15 (DDC), 10→4→10.
Greeter copy synced; greeter.qml load-tested on every promote.

Open, in order:
1. Shell memory: grows ~70–85 MB/h from 280 MB, levels off ~720–750 MB
   (RSS 1.17 GB). gc() frees nothing: held, not garbage. Not images (all
   sized). Next: run with QV4_MM_STATS / bisect services by disabling one
   at a time in a test session; suspects are periodic JSON parsers (Limits
   watch, T3Code, Updates) and per-second rebinding.
2. Reboot once: the GRUB line is in grub.cfg (Nov 5 23:10), the running
   kernel (booted 18:42) predates it. Then the seamless greeter handoff.
3. sudo system/install (kuwai-wake: alarms that wake the laptop) — not done.
4. Screensaver all night under Caffeine: film decoded 6 h on both screens.
   Option: after an hour, stop the film (clock on black) or screens off.

## STATUS (2026-11-06 late) — ratings and what gates 9.5

Notch rest 9.3 · hover 9.0 · Usage 9.3 · Bluetooth 9.0 · bell list 8.8 ·
center 8.8 · screensaver 9.0 · updates 9.0 · clipboard 8.5 · lock/login 6.5 ·
CPU 9.2 (idle ~3 %) · memory 8.8 (290–380 MB plateau, no per-open leak:
60 opens of a panel ended lower) · reliability 8.5 (3 load outages today,
gates now: offscreen load test + anchor-line names) · consistency 8.0
(tokens: sizes 62, durations 111, hex 70).

Gating 9.5, in order:
1. Lock/login: user runs the GRUB line, then the seamless greeter → shell handoff.
2. ~~Panel-level load check~~ done differently: promote rolls stable back to
   the last good commit if the new shell doesn't load (live-tested: 4 s).
3. Tokens to zero: sizes (62) and the remaining durations (111) by meaning.
4. Clipboard onto the island's row/header style; one Row/Header component
   shared by NotifsPanel, T3Panel, BluetoothPanel, UsagePanel.
5. Notifications: toast → its row in the center as one motion (bursts
   already fold into one toast with a count).
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
      onto Theme tokens (bin/kuwai-tokens ratchet: sizes 62, durations 131,
      hex 70 → 0); one row style (NotifsPanel/T3Panel/BluetoothPanel: 46 px,
      Theme.r2, 0.07 hover) used by the center, launcher, clipboard; one
      header style (tTitle3 semibold + right meta in tFootnote tertiary); one
      empty state (glyph + tSub line); one button set (PillButton, RestMark).
      Migrate file by file, lowest-traffic first, screenshot before/after.
- [ ] Long uptime: read ~/.local/state/kuwai/memlog.tsv after 2+ days; find what grows.
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
   sample Pss_Anon per surface opened. kuwai-check's memory gate blocks
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
4. Tokens: bin/kuwai-tokens ratchet in kuwai-check (baseline in
   docs/design/tokens-baseline.json, only goes down). sizes 62, durations 165,
   hex 70. Keep migrating module by module; run `kuwai-tokens --update` after.
5. Popovers: bell on components/Popover; status menus on TrayMenu;
   AgentStack keeps its own popup on purpose (marks fly into rows).
6. Super+N: already island = quick switch, Center = deep list (+ passwords).
7. Login gap: needs the user's GRUB line (see below); then seamless handoff.
8. Clipboard: copies vanished when the copying window closed (drop-down
   kitty is its own process); wl-clip-persist starts at login once installed.
9. Later: Wallpaper Engine video wallpapers (owning WE + steamcmd, or
   licence-clean sources); meters baseline-align.

## Earlier — in progress
1. **Polkit agent (kuwai-auth)** — BUILT 2026-11-01: shell-auth/shell.qml + systemd/kuwai-auth.service
   (linked into ~/.config/systemd/user, started by startup.lua; hardened: no crash handler/dumps,
   LimitCORE=0, NoNewPrivileges, no file watcher, software renderer ~140 MB, exit 3 = another agent
   → OnFailure KDE agent). Picks *your* identity when polkit offers several; submits only when PAM
   asked. Remaining: user runs `pkexec true` (enter + Esc paths), `kuwai auth` subcommand
   (install/status/test), doctor check. Original brief: — island-styled, *separate small Quickshell process*
   (`shell-auth/`, own systemd user unit, Restart=on-failure), Quickshell.Services.Polkit
   (PolkitAgent/AuthFlow → polkit-agent-helper-1; never handle the password ourselves; clear
   field on close; no logging; show action id + requesting program + user; Overlay layer,
   exclusive keyboard, dim backdrop; queue while locked; fallback: start
   plasma-polkit-agent if kuwai-auth fails to register). Replace plasma-polkit-agent in
   kuwai startup. Test with harmless `pkexec true` / dry runs before going live.
2. **Updates panel in the island** (no kitty/sysup spawn; sysup stays for terminal):
   list repo + AUR updates (checkupdates, paru -Qua), per-package toggles, release notes,
   Update selected/all; repo via pkexec pacman (prompt = kuwai-auth), AUR builds as user,
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
- kuwai-auth v2: grows out of the island's exact rest shape (shell publishes
  $XDG_RUNTIME_DIR/kuwai/island.json), island springs, Theme tokens (config/ components/
  assets symlinked), avatar (~/.face rounded via magick), tries left + lockout countdown from
  faillock, Caps Lock tag, success check, accent buttons. Software renderer (no MultiEffect /
  ClippingRectangle there). Tested with pkcheck (pkexec can't run in Claude's sandbox).
- Cancel counts as a faillock failure (polkit socket helper; KDE's too) → tell user; propose
  deny=10 unlock_time=120 (Omarchy). User must run it (root).
- Screens.focusedName went stale (Quickshell focusedMonitor) → panels opened on the other
  monitor holding exclusive keyboard = "launcher stuck" / likely the vicinae Super+Space issue.
  Now tracked from raw events + hyprctl probe before every keyboard open.
- Theme picker: palettes on cards + preview strip; Colours mode (theme/wallpaper/dark/light =
  HyDE enableWallDcol via `kuwai-themes colormode`); stable fav sort; island surface 1120 wide.
- Theme.qml: accent follows HyDE mode (theme.dcol → kitty.theme → wall.dcol), 400 ms blend,
  Theme.onAccent. Island rest: no padding hole beside the time (balanced only within 10 px).
- Pills: current = numbered capsule (iOS page control); guests hollow after a gap.
- Keyboard-opened panels morph too (fast critically damped tier) instead of snapping.
- Media card: click → focus the playing window (title/class match, else MPRIS raise);
  right-click → sound panel.
- Tray menus: components/TrayMenu.qml (QsMenuOpener, drill-down submenus, theme glass).
  NOT yet seen by eye — ask user.
- config/Paths.qml: no hardcoded ~/Projects/rice in QML. doctor checks kuwai-auth + faillock.

## Decisions / answers given
- AUR in Updates panel: review ON by default and never silently skipped: per-package PKGBUILD
  diff (git diff in paru clone cache) shown in-island with a reusable DiffView/CodeBlock (QML;
  diffs.com/shadcn patterns ported — the shell is QML, not web: no CSS/shadcn directly);
  "Approve" per package; option "trust updates from this package" is explicit per package.
- Login: recommend greetd + a Quickshell greeter reusing the rice lock (DMS's dms-greeter
  approach) so login → lock look identical; SDDM (astronaut theme now) stays until tested.

## Done 2026-11-02 (morning)
- Software Update: bin/kuwai-update (+ detached systemd job kuwai-update: survives shell restarts,
  pacman writes to a file not a pipe, single-instance lock, inhibits sleep/shutdown), Updates
  service (follows update.jsonl, rejoins after restart, watchdog), UpdatesPanel (list / review /
  run), DiffView, island ring + %, hover chip, alert "Review", System row. Routine version bumps
  detected (versions/hashes normalised). Review = diff since the commit that built the
  installed version. One island Back row (Island.innerBack) for panel levels.
- kuwai-auth: vendored tokens (no links), `kuwai auth diff|status`, doctor audit (no IPC/process
  in config/components, 4 known commands), pacman prompts named "Install system/AUR updates".
- Shell started via Hyprland (kuwai-shell), not as a child of whatever terminal ran it.
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
kuwai-auth 127 MB, brightness daemon 20 MB, voxtype launcher 3 MB, watchers <1 MB each.
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
- Rename rice → kuwai (units kuwai-auth/kuwai-update, bins, layers) in one pass.

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
    bin/kuwai*, ~/.local/state/kuwai); entry already finds ~/Projects/kuwai.
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
