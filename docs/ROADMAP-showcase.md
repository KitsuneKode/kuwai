# kuwai — everything between now and a showcase

Written 2026-11-16 after your two notch screenshots. Companion to
[PLAN-launch.md](PLAN-launch.md) (in-flight work, the first 12 issues, order of
the first weeks). This file is the whole list: interaction, panels, packages,
reproducible machines, media, look, kittymux, the component layer, what to take
from every reference, and the order.

Evidence is from this machine on 2026-11-16 unless marked "from the earlier study".

---

## 1. The earlier issues, in plain words

| # | What it means | State |
|---|---|---|
| Greeter brightness | The login screen had its own brightness script: every key changed every screen, each on a different curve, so they drifted apart. | Fixed on `polish/fluid-motion` (focused screen only). Needs merge + one logout. |
| Login black screens | Two separate compositors hand the GPU over. The welcome is cut instead of faded, the greeter's audio services slow its shutdown, and the desktop pops in. | Plan: fade to black → black hold → wallpaper fades in with the notch growing. Shorten by masking the greeter user's audio services. |
| 4.84 GB at boot | voxtype keeps its 2.4 GB speech model in RAM (3.1 GB). Then shell 0.47, Hyprland 0.4, Docker+searxng 0.3, easyeffects. | Your call on voxtype (int8 / GPU / load on first use). |
| Inconsistencies | Two brightness stacks, `rice-*` vs `kuwai-*` names, raw sizes/durations still in code, live shell on the dev copy. | Partly fixed; rename + tokens open. |
| Re-implementations | Hand-written code where a maintained thing exists (greeter brightness, base64, HyDE scripts for theme/wallpaper). | Listed in PLAN-launch §5. |
| Implicit state machines | Behaviour decided by many independent flags and timers (223 timers, 118 spawned processes) instead of one named state. | Model the 6 risky ones (login, idle, island, agent attention, clipboard, updates). |
| kittymux × notch | The notch should hear agents through their own hooks, not by reading the screen and typing into panes. | Panacea's hook approach found; needs your yes to install hooks. |

## 2. Issues we had missed

1. **The live shell reloads on every file save.** It runs from `~/Projects/rice/shell`
   with file watching on, so any edit (yours, mine, another agent's) restarts parts
   of your desktop, and the dev-reload memory growth applies. Run from stable;
   develop in worktrees.
2. **Three unmerged streams**: the 75-file quality worktree, `polish/fluid-motion`,
   another session's edits to menus/buttons/cards in the main checkout. Each day
   apart makes the merge worse.
3. **SF Pro can't ship.** Apple's licence limits it to Apple platforms. Fine on your
   machine; a public install needs Inter (or another open face, with optical size)
   as the default and SF Pro as an optional upgrade.
4. **Browser media shows no picture and raw titles.** Hotstar sends no artwork and the
   title `Watch Pirates Of The Caribbean: … - JioHotstar`; the card shows
   "Watch Pirates Of The C…" and "Mozilla zen". (§5)
5. **The glance strip is twelve unlabeled rings**: CPU, memory, battery, temperature,
   then eight AI quotas, all the same size and shape. You can't tell which is which or
   which one matters. (§4)
6. **The biggest target does the narrowest thing.** The clock sits in the centre of the
   notch and clicking it opens the calendar; everything else needs a trip to the sides. (§3)
7. **Greeter hardcodes your monitors** (`desc:California Institute…`, `desc:Acer
   XV272U`). On anyone else's machine the login screen uses defaults.
8. **34 files depend on HyDE** for wallpaper and colour. Without HyDE, kuwai has no
   theme pipeline.
9. **First keystroke may be lost** when a panel opens (a new layer gets the keyboard a
   frame late; Panacea retries focus each frame for 30 frames). Unverified here.
10. **No support bundle.** Someone else's bug report can't include logs, versions,
    monitors and settings in one redacted file.
11. **No first-run, no tested uninstall, no clean-VM install.**
12. **`caffeine-mode.service` fails every boot**; greeter user runs pipewire/wireplumber
    for nothing.
13. **Tokens in files instead of the keyring** (T3 token: mode 600, read-only scope;
    acceptable, keyring is better).

## 3. The notch: how you interact with it

Principle: **the biggest target does the most common thing; every side is a door;
nothing important hides behind hover.**

- **Click anywhere on the resting notch → the full view** (the hub). The time inside
  the hub opens the calendar, and the clock still flies there (the shared-element
  motion is kept). Today the centre click goes to the calendar.
- **Sides stay doors**: left (what you're in / which agent) → that app or Agents;
  right (status) → its panel. Capsules either side stay doors to their panels.
- **Right-click = the quick menu of the thing under the pointer** (already true for
  Wi-Fi/battery; make it true everywhere, same menu component).
- **Middle-click**: nothing, or one documented action (do-not-disturb). Never a
  different panel per region.
- **Scroll**: left half volume, right half brightness (planned), with the HUD growing
  from the notch.
- **Pull down = hub** (exists). **Flick up = close** (exists).
- **Hover timing**: today 220 ms in, 300 ms out. Keep 300 ms out (crossing a gap
  shouldn't close it). Replace the fixed 220 ms in with intent: open when the pointer
  slows or rests ~120 ms over the notch, never while it's passing through to the top
  edge (the proximity code for Minimal/Hidden already reads intent; use it here).
  Hover shows the glance only; the full view always answers a click or a pull.
- **The glance shows what changed, not everything.** An agent waiting, a download
  finishing, a limit close to reset. When nothing changed: time, date, one status
  line. The current glance always carries the full ring strip.

## 4. Usage, system monitor, processes and ports

### The ring strip (screenshot 2)
Split it into two labelled groups and show exceptions only:
- **This machine**: CPU, memory, GPU/temperature, battery. Hidden while normal; a ring
  appears when its value crosses a threshold (CPU > 70 % for 10 s, memory > 85 %,
  temp > 85 °C, battery < 20 %) with the number inside.
- **AI limits**: one ring per provider (Claude, OpenAI, Cursor, Grok…), showing the
  tightest window across accounts, coloured by headroom (green → amber → red), the
  logo inside, "62 % · 1 h 12 m" on hover. Hidden while every provider has > 50 %
  left, unless you pin it.
- Empty state: one quiet mark ("All good") instead of twelve rings.

### Usage panel
- Rows by **provider → account → window** (session, weekly), each with a pace notch
  (where you'd be at an even pace) and the reset countdown (kittymux has the pace
  notch already; reuse its maths).
- **Projection**: "at this pace you hit the limit at 16:40" — the number people
  actually act on.
- **Who is spending it**: which kittymux pane / T3 thread used the most in the last
  hour (kittymux knows panes; T3 knows threads).
- 7-day history sparkline per account. Last-good values stay with "updated 4 min ago" /
  "offline" / "token revoked" labels (t3code-bar's rule).

### System monitor (Vitals)
- **Group by app, not process**: Zen's 20 content processes are one row, "Zen 2.9 GB".
- **What changed**: growth since boot / since last look, so a leak is visible.
- Per-app GPU memory (nvidia-smi), CPU sparkline, kill / restart in place.
- Boot budget card: what started at login and what it costs (today's 4.84 GB table,
  live).

### Process and port killer (launcher `!` mode → one "Activity" search)
- Search by app name, **port** (`:3000`), **project folder** (the process's working
  directory: "kill the dev server in kuwai"), and command line.
- A dev server started in a kittymux pane shows its pane: **Jump to pane** first,
  Kill second (the agent may want it).
- Safe kill: SIGTERM, wait 3 s with a countdown, then offer SIGKILL. Protected list
  (Hyprland, the shell, pipewire, polkit agent) can't be killed from here.
- Ports show protocol, address (localhost vs 0.0.0.0 — exposed to the network is
  flagged), and the owning project.

## 5. Media: pictures and titles

- **Clean titles**: strip `Watch `, ` - <Site>`, ` | Netflix`, `(Official Video)`;
  parse `S1 E3`. Subtitle = the site from the URL ("JioHotstar"), not the browser name.
- **Art fallback chain**: player artwork → **a live frame of the playing window**
  (Quickshell's ScreencopyView of that toplevel; local, no network, updates every few
  seconds while the card is visible) → site icon → nothing (never a grey note).
  Optional, off by default: a poster lookup by cleaned title (sends the title to a
  service; cache it).
- Video gets the progress bar (the player reports length) and the frame; music keeps
  the cover and the waveform.
- Caveat: some protected streams capture as black; then fall back to the site icon.

## 6. Packages in the notch, reproducible machines, rollback

### Search and install (launcher `+` mode, then a Software panel page)
- One search across repo packages, AUR and Flatpak, ranked by match, popularity and
  whether it's installed.
- Details: description, size, dependencies it would pull in, last update, AUR
  standing (votes, maintainer, age, out-of-date — Updates already computes this).
- AUR installs go through the same review as updates (PKGBUILD shown, approve once,
  "established" badge), then one job via `rice-update` with the rice-auth prompt;
  progress lives in the notch.
- Remove: "also remove what it pulled in" (`pacman -Rns`), with the list shown first.

### A machine you can carry (`kuwai export` / `kuwai restore`)
- `kuwai export` writes one file: explicit repo packages, AUR packages, Flatpaks,
  enabled user/system units, kuwai settings, monitors/keyboard, theme and wallpaper
  list. **No secrets.** Optional: commit it to a private dotfiles repo.
- `kuwai restore <file>` on a new machine: shows the difference from what's installed,
  then runs one reviewed job.

### Rollback
- Root here is ext4: no filesystem snapshots. What's possible today:
  - **Undo last update**: `rice-update` logs exactly which packages changed; keep
    the previous versions in the package cache and offer "Undo" (pacman -U of
    those versions) in Software Update.
  - **Settings history**: keep the last 10 versions of kuwai settings and your Hyprland
    user files; "Restore yesterday's settings".
- For new installs: document btrfs + snapper + a boot-menu snapshot entry (Omarchy's
  approach, from the earlier study) as the recommended layout.

## 7. Look: colour, glass, shaders, layers

- **Colour**: neutral glass stays; ink (text on the wallpaper — lock clock, greeter)
  is solved against the actual crop for contrast; one accent, from the theme or the
  album art, never both at once. AI providers keep brand colours only inside their
  logos.
- **Glass**: one material component (tint, blur, rim, shadow tiers) used by the
  island, panels, toasts, menus and the centre; today menus draw their own stacked
  shadows.
- **Three shader moments, no more**: the wallpaper change (a short event on its own
  layer), the needs-you glow (soft bloom, then still), the unlock reveal. No
  full-screen shader running continuously.
- **Compositor layers**: one namespace per surface; blur only where the tint is
  translucent; `no_anim` where the shell animates itself; nothing new under `rice-*`
  unless it wants the glass blur (that rule can't be undone later).

## 8. kittymux

- **Hooks first**: Claude Code / Codex `PermissionRequest` and notification hooks
  report waiting with the exact tool and command; Allow/Deny answered through the hook
  (offered only when the whole command fits on one line). `answer --expect` stays as
  the fallback for agents without hooks.
- **Live activities from panes**: tests, builds, long commands → progress, then ✓/✗ in
  the notch, with Jump.
- **Overnight digest** as the welcome-back moment.
- **Sidebar rebuild** (plan 015) finished and on by default; one-line rows; program
  glyphs.
- **First 30 seconds**: `kittymux demo` already exists — make it the README's top
  line and the first clip.
- **Unverified agents**: agy, cursor-agent, opencode, gemini — one real capture each.

## 9. kuwai-ui: a component layer like shadcn, for Quickshell

Today: 44 components, 8 under `components/ui`, a kuwai-ui skill, a token ratchet.
Rows, headers and empty states still differ between panels. Make the layers explicit
and enforced:

| Layer | Contains | May import |
|---|---|---|
| 0 Tokens | `Theme` (colour, type roles, radii, springs, elevation) | nothing |
| 1 Primitives | Glass, Text roles, Icon, Ring, Meter, Spring, Fling, Pressable, FocusRing, FluidHighlight, KeyCap, Tip | tokens |
| 2 Components | Row, Section, Header, EmptyState, Chip, Button, Segmented, Toggle, Menu, Popover, Card, Sheet | 0–1 |
| 3 Patterns | Panel (size, header, back, keys contract), Glance, Capsule, Moment, Toast | 0–2 |
| 4 Surfaces | the panels and modules | 0–3 + services |
| Services | data and processes, no UI | other services |

- **Enforced by a check** (`bin/rice-layers`): a component that imports services, or a
  surface with a raw size/duration/colour, fails promote (the token ratchet already
  does the second half).
- **The gallery is the docs**: `test gallery` renders every component in every state;
  the verify harness screenshots it into a docs site (light, dark, 200 % text,
  reduced motion), like shadcn's pages.
- **`kuwai add <component>`**: copies a component and its primitives into any
  Quickshell config (a small registry file). This is the part other ricers can
  use without adopting kuwai — the notch, the rings, the fluid highlight, the
  menus. It is also the strongest reason to star the repo.

## 10. What to take from every reference

| From | Take | Leave |
|---|---|---|
| **Panacea** (MIT) | hook-based Allow/Deny; installer flags + timestamped backups + `custom/` dirs kept across updates; Update button + What's New; rebindable shortcut sheet; live mock-ups in settings; FocusGrabber; small event sounds | 7.6k-line shell.qml; unlicensed wallpaper pack |
| **pocket-dots** (GPL, ideas only) | wallpaper change as a short layer event with a fallback that really sets the image; ink solved against the crop; one namespace per layer | opaque black shell; blur behind every window |
| **t3code-bar** (MIT) | alert only on a change; keep last-good data and say stale/offline/revoked; keyring for secrets; contrast checked on the 8-bit value | a 1 s refresh loop |
| **Omarchy** (earlier study) | one menu tree for everything incl. install/remove; snapshots in the boot menu; an in-app manual; opinionated defaults with an uninstall | — |
| **DMS** (earlier study) | process list, control centre polish, greeter reusing the lock, IPC CLI | — |
| **Caelestia** (earlier study) | dashboard (media + performance + weather), lock with media | — |
| **end-4** (earlier study) | overview with live previews; AI sidebar | — |
| **HyDE** | themes as installable packages → a kuwai theme format | being a dependency |
| **Apple** | tap = expand; Live Activities; Control Center modules; Spotlight-style actions | — |

## 11. The showcase

- **Positioning**: "an AI-native desktop: your notch knows which agent needs you."
- **README**: a 20 s hero video, `kuwai demo` (fake agents and music in the notch, no
  setup), real screenshots from the gallery, GIFs under 2.5 s per feature.
- **Clips** (PLAN-launch §6) plus two new ones: the live video frame in the notch, and
  "kill the dev server on :3000 → jumps to the pane that started it".
- **Releases**: v0.1 with a changelog; a docs page for kuwai-ui components.
- **Order**: kittymux first (portable), kuwai-ui components second (useful to every
  Quickshell user), the full rice third (r/unixporn, once install works on a clean VM).

## 12. Order of work

1. **Merge everything in flight** (quality worktree, `polish/fluid-motion`, the other
   session's edits) and run the live shell from stable.
2. **Notch interaction** (§3) and **glance/rings** (§4 strip) — what you see most.
3. **Media titles and art** (§5).
4. **Activity search** (processes, ports, projects) and **Vitals by app** (§4).
5. **kuwai-ui layers** + layer check + gallery (§9) — before more surfaces are added,
   so new ones land on the system.
6. **Login reveal**, **greeter monitors from your config**, **voxtype memory**.
7. **Packages in the notch** + **Undo last update** + **export/restore** (§6).
8. **Portability**: HyDE optional, Inter default, installer (Panacea's shape), clean VM,
   support bundle.
9. **kittymux hooks + live activities** (§8).
10. **Atmosphere** (wallpapers, ink, the three shader moments) and the **showcase** (§11).

## Needs you
- Merge `polish/fluid-motion` (and the quality worktree) — goes live on reload.
- Yes/no on installing agent hooks into Claude Code / Codex settings.
- voxtype: int8, GPU, or load on first use.
- Click model in §3: OK to make the centre open the hub instead of the calendar?
- Poster lookup for videos (sends titles to a service): on or off by default?

## 13. Shipped 2026-11-16 (night), all live on feat/assistant-agent

Merged: the quality worktree (plans 001–010 slices), `polish/fluid-motion`, the
stale main-checkout edits (as their own commits). Fixed on merge: the new
ConfirmationDialog broke the shell's load (Qt 6.12 read-only implicitWidth); the
offscreen load test does NOT catch that class (it passed the broken commit) —
the live `test compile` sweep does. Gate gap to close.
Then: centre click opens everything (calendar = its time chip); Keep awake modes
(Manual / At login / While work runs); media titles + site ("JioHotstar"); a film's
frame as its cover (only the window showing it; never on the lock); one ring per
agent provider, machine rings only when high; launcher dock row (⌥1–8); kuwai-fetch
(animated GIF + fastfetch in kitty); wallpaper changes grow out of the island
(WallFx + wallreveal shader; 1.35–1.41 s end to end, measured).

## 14. From pocket-dots' credits and Impasto (read 2026-11-16)

| Repo | ★ | Licence | Take |
|---|---|---|---|
| andreumassanet/impasto | 470 | GPL | Closest peer (island + liquid glass). Ideas: material per layer (classic/glass/liquid), mic/camera/screen marks beside the time, widgets on the wallpaper (right-click to arrange), a "servers you have running" panel, palette reaching Zen/Spotify/Nautilus, public-domain paintings as the bundled wallpapers |
| 43PR/dotfiles | 2 027 | MIT | Installer with automatic backups, preset themes + wallpaper-based colour |
| snes19xx/surface-dots | 831 | none | Screen shaders bound to keys (look only; no licence = no code) |
| VirtCode/hypr-dynamic-cursors | 766 | MIT | Cursor tilt/stretch + shake-to-find: a cheap "alive" moment (plugin; optional) |
| CluelessCatBurger/wl_shimeji | 206 | GPL-2 | Desktop pets — not our taste |
| fdeox/termspot | 14 | MIT | CRT Spotify theme — not our taste |
Default wallpapers: public-domain paintings (The Met open access, CC0) in the
blue-hour / fog / near-black set — solves licensing and taste at once.

## 15. The theme to build first ("kuwai Night")
Near-black glass (#111114 tint as today), one vivid accent taken from the
picture, neutral ink solved against the actual crop, the same painting on lock
and greeter, a kuwai theme format (palette + wallpaper set + accent rule) that
doesn't need HyDE; HyDE themes import into it.

## 16. Audit, 2026-11-16 late: remove, fix, leaks

**Removed tonight:** components/Popover, notifications/UsageCard, waybar/custom-dunst.jsonc
(nothing referenced them). Every bin/ script is referenced somewhere.

**Remove or move next (your call):**
- `plugins/kitty-sidebar/` (C++ plugin spike + evidence) → kittymux's repo or delete.
- `refs/` (1.5 GB of reference clones, untracked) → move to Depot.
- Running leftovers: `caffeine-mode.service` (fails every boot), `nm-applet`,
  `hyde-config`; Docker + searxng at boot (~0.3 GB) → socket/on demand.
- Two superseded worktrees (`t3/notch-usage-limits`, `fix/security-recovery`).
- `~/.cache/rice/aur` build leftovers (8.5 GB; the merged updater now prunes new ones).

**Memory:**
- No object leaks found: every dynamically created Process/Timer/notification
  destroys itself (Clipboard, Display, Kittymux answerer/runner, Notifs jumper,
  Ollama notifier, Alarms, Reminders, VoxtypeHost checked); growing lists are
  capped (Updates log 400, Switcher MRU 200) or rebuilt per read (Alerts).
- No helper pile-up: 11 helpers under the shell, all from the last reload.
- The measurable growth is the dev channel: memlog Pss_Anon 269 → 418 MB in an
  hour with ~20 hot reloads tonight (known dev-reload leak). Run the live shell
  from stable (`~/.local/share/kuwai`, watchFiles off) and soak 8 h before
  calling anything a leak.
- New code tonight frees what it uses: WallFx's layer and images exist only during
  a change (`cache: false`), the film frame captures only while its card shows,
  FluidHighlight's per-frame follow runs only while something is lit.

**Gate gap:** the offscreen load test passed a commit that failed to load live
(a type error in a lazily compiled file). `rice promote` must run the live
`test compile` sweep over changed files (rice-check already has the loop).

## 17. From Clove (keshav-exe/clove, MIT, a macOS notch app for coding agents)
Read its site and its 14.6 s demo video (frames at 2 fps).
1. **Sections switched by hover**: section icons sit in the panel's top edge; the
   pointer passing over one switches it, content crossfades (with a little blur).
   → the hub's pages (Now, Agents, Usage, System) as hover tabs in the notch's ears.
2. **Linked hover between a chart and its legend**: a dot-matrix storage bar;
   hovering a block lights its legend row and rewrites the header line ("Photos
   20.5 GB · your library takes…"). → disk/memory/usage bars in Vitals and Usage,
   and kuwai's ring "hot line" generalised to every chart.
3. **One big number + short list + one action** ("5,994 tokens every session
   spends on skills nobody called") → Usage and Cleanup headers.
4. **AI hygiene ("Cleanup")**: skills/commands/subagents no agent called in 30/90
   days and the tokens they cost every session; agent leftovers on disk; move to
   Trash with undo. → a kuwai Cleanup page: unused skills (you have many), stale
   worktrees, rice/bun/agent caches, old sessions.
5. **Skills search from the notch**: search every SKILL.md; ↩ inserts `/name`
   into the prompt you came from, ⌥↩ copies. → launcher `/` mode, typed into the
   focused pane like emoji mode.
6. **Now**: running agent sessions and dev servers with memory and Stop. → the
   Agents panel + the Activity search (ports → the pane that started them).
7. **Keys**: API keys exported in plain text in shell profiles moved to the keyring,
   the line rewritten to read from it. → `kuwai keys` (Secret Service), a security
   win that demos well.
8. **Quiet when closed**: a closed notch scans, polls and animates nothing.
   kuwai mostly does this; the Usage watcher and some per-second probes don't.

## 18. Notch shape, motion and pills — order (2026-11-17)
Sources: Clove's NotchShape/NotchView/NotchModel (MIT, read in full), its demo
video; Skiper's "Dynamic island" (Pro-gated: no code read; it follows Emil's
animations.dev island lesson: idle/ring/timer/record/music/airdrop states).
1. **Shape** (done): continuous ear flares that grow 9 → 14 px with the island;
   bottom corners already continuous 14 → 30 (Clove 12 → 26).
2. **Spring** (done): grow ζ 0.8 (~1.5 % give), shrink and keyboard critically damped.
3. **Sections** (done): Agents / Usage / System / Cleanup switch in place, ⌥1–4.
4. **Content swap inside a pill** (next): when a live pill changes state (timer →
   done, dictation → writing, agent working → waiting), the old content leaves
   in 80 ms (opacity) and the new arrives 60 ms later with opacity + scale 0.97 from
   the top and a 2 px blur that clears — one container, the shape springs once
   (Clove's contentReveal; Emil's popLayout + blur). Today they cross-fade in place.
5. **Pill states** (Skiper's set, kuwai's way): ring (call/alarm), timer counting
   on the side, recording (red dot + time), dictation (exists), music (exists),
   AirDrop-like send = KDE Connect "sent to phone" with a progress ring.
6. **Ears as live slots** (Clove's LiveEars): the resting notch shows one icon per
   side only while something works, the icon arriving after the ear opens (scale
   0.7 → 1, bounce 0.2, 80 ms late) — kuwai's split capsules, tightened to that rule.
7. **Linked chart ↔ legend hover** in System and Usage; one big number on top.
8. Then theme (kuwai Night), kittymux ask-mode hooks, install/docs.

### 18 — status, 2026-11-17 01:00 (all on feat/assistant-agent, stable = 8636ccd)
1–3 done (shape, spring, sections). 4 done: capsule swap (snapshot out 110 ms,
new in from 0.97 through a blur, width springs) and the notch's own activities
reveal the same way. 5: Skiper's set already existed (dictation, recording,
timer, update, song, music; an alarm ringing is a card); "sent to phone" needs
kdeconnect-cli (not installed). 6 done (icons arrive after their capsule
opens, from 70 %). 7 done for memory (LinkedBar in System). 8: Kuwai Night
built and applied; Allow/Deny through mux-ask built and tested end to end
(installing the hooks into ~/.claude*, ~/.codex is the owner's step: the
session's permission check refused to edit agent settings); README updated;
stable promoted after every gate passed. Not done: a clean-VM install, the
font question (kept SF Pro), "sent to phone".
