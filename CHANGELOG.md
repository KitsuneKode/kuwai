# Changelog

Versions follow [Semantic Versioning](https://semver.org/). Until 1.0 a minor
release may change settings, binds or file layout; when it does, the migration
that carries an existing install across ships with it (`kuwai migrations`) and
is listed here.

## Unreleased

### Install and updates
- Rollback undoes migrations. A migration names what it changes in
  `# touches:` lines; the runner copies those paths first, puts them back at
  once if the migration fails, and `kuwai rollback` (and a promote or
  update-self that fails partway) puts them back when returning to a release
  that doesn't have that migration. A path you changed since is kept and named.
  `kuwai migrations --undo N…` does it by hand.

## 0.1.0 — 2026-11-25

The first release. Kuwai is a desktop for Arch Linux: its own Hyprland session
(Lua config, Hyprland 0.57 or newer) and its own Quickshell shell, built
around one status surface at the top of the screen, the island.

An earlier `0.2.0` label was written into `VERSION` and this file before
anything was tagged. Nothing was ever released under it, and everything it
listed is part of 0.1.0.

### Install and updates
- `install.sh` with `--dry-run`, `--deps` (packages from `packages/core.txt`,
  `optional.txt`, `fonts.txt`; `--yes` for no prompts), `--doctor` and
  `--uninstall`, which puts back everything it replaced, user services included.
- Kuwai is its own login session. Its Hyprland config lives in
  `~/.config/kuwai/hypr/`, so the plain Hyprland session and `~/.config/hypr`
  stay yours. An install that used `~/.config/hypr` moves across with
  `./install.sh --separate-session`.
- A login screen on greetd (`sudo greeter/install`, `--undo` restores the one
  you had) that shares its design and password pill with the lock screen.
- The stable channel. Your session runs from `~/.local/share/kuwai`.
  `kuwai promote` moves it forward only after `kuwai-check` and a load test
  pass, and rolls back on its own if the shell fails to come up.
  `kuwai rollback` returns to the previous release.
- `kuwai update-self` updates stable to the newest release tag, checks it,
  runs its migrations and restarts. `KUWAI_UPDATE_REF` picks another ref, and
  a stable copy that is already ahead is left alone.
- `kuwai version` prints the version, the commit stable runs and the channel.
- `kuwai migrations`: when a release changes something an earlier one left on
  disk, the change is made once, in order, and recorded.
- The shell runs as `kuwai-shell.service`, so systemd restarts it when it
  crashes. `kuwai doctor` checks the session, notifications and shell.
- `kuwai backup` snapshots your own files, with diff and restore.
  `kuwai export` writes a portable machine manifest, with secrets left out.

### The island
- The notch holds the time and whatever is live: a recording, dictation, a
  timer or music. Hover for a one-row glance; click or pull it down to open
  everything. It grows and folds like the Dynamic Island, with continuous
  flared shoulders and a spring when a capsule changes state.
- Capsules float beside it, each with its own state colour: your agents
  (kitty panes and T3 Code threads, one mark per agent), an agent waiting on
  you (its own orange capsule), usage limits (which only say when you can
  carry on), system news and minimized windows (Super+O).
- Agents, Usage, System and Cleanup are sections of one panel, switched from a
  header strip or with ⌥1–4. Every panel works from the keyboard.
- Agents: calm cards with a status pill, grouped by where they run. A working
  agent shows its last three steps and its context fill. Answer Allow or Deny
  (Claude Code, Codex, T3 approvals) from the notch, through the agent's own
  hook; you never type into the pane.
- Usage: one bar per limit and account (Claude, Codex, Devin and more), plus
  what each agent spent and the tokens it used, read from this machine's logs.
- System: memory by app, with a browser's processes counted once.
- Cleanup: skills no agent has used in 30, 90 or 180 days, what they cost
  every session, and duplicates. Everything goes to the Trash and Put back
  restores it.
- Privacy dots for the mic, camera and a shared or recorded screen, each
  naming who is using it.
- While you were away: after the screensaver or an unlock, a short recap of
  what happened.
- Idle projects (with [sweep](https://github.com/KitsuneKode/sweep)): old
  projects holding space worth getting back.

### Notifications and the center
- Kuwai runs its own notification server, with a Sonner-style toast stack.
  Important notifications peek out of the notch, and apps can offer their own
  buttons there.
- One notification center (Super+N), with Notifications, Sound (a per-app
  mixer and outputs) and Controls (Wi‑Fi, Bluetooth, DND, Night Shift,
  Caffeine, mic, Reduce Motion, battery, brightness).
- Swipe a notification away and undo a clear. Stale news leaves on its own.
  Chat messages never show on the lock screen.
- One rule decides who may interrupt. An agent asking you reaches you
  everywhere. Under Focus, DND or screen sharing nothing grows the notch.
- GitHub and Gmail feeds (`kuwai feeds`). Bot reviews and failures toast; the
  rest waits in the center.

### Launcher, clipboard and assistant
- Launcher: apps, a dock of what you use most, a real calculator (units,
  currency, percentages), processes and ports (`!`), and packages from the
  Arch repos and the AUR (`+`).
- Clipboard island (Super+V): a shelf of cards with fzf search, Quick Look,
  actions, OCR, pins, rendered Markdown, code and Mermaid, and masked secrets.
  A delete is held for five seconds before it is final.
- Assistant (Super+Ctrl+Shift+A): a local agent on Ollama that uses tools and
  asks before it acts, with sandboxed chats.
- Timers, a pomodoro, reminders and alarms that grow out of the island; a
  shortcuts sheet (Super+/); settings with search and a reset beside every
  changed row.

### Look
- 13 themes, each with a native `theme.toml` and `palette.toml`: Kuwai Night,
  Aurora, Chrome Sunset, Crimson Noir, Deep Field, Earthlight, Garage, Matcha,
  Neon District, Pixel Dusk, Sakura Night, Violet Hour and Void. Wallpapers are
  downloaded, pinned and credited, never shipped in the repo.
- `kuwai look`: an atomic palette and wallpaper switch with WCAG contrast
  checks, user templates and hooks. `kuwai-look install` adds a theme from a
  repository after validating it.
- Wallpaper changes grow out of the island. Live wallpapers get a
  GPU-decodable copy, so the shell never decodes video in software.
- Inter, with its optical sizes, is the default face (SF Pro is used if you
  have it). Dates and times follow your locale.
- Accessibility: every surface is named for screen readers, and there are
  Increase contrast and Text size settings.
- `kuwai demo`: a 45-second tour of the island with pretend agents.
  `kuwai-wallcheck` tells you whether a picture makes a good wallpaper.

### Under the hood
- Design tokens for every size, duration and colour (`bin/kuwai-tokens
  --check`), layer and HyDE-isolation gates, and a comment ratchet.
- `kuwai-rehearse --gate` renders every island panel in every state in an
  isolated window, at standard and large text, before a promote.
- `kuwai-update` builds AUR packages with a storage report, bounded caches and
  cleanup. HDR follows the signal on the wire (`kuwai-hdr`).
