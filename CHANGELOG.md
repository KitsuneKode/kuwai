# Changelog

Versions follow [Semantic Versioning](https://semver.org/). Until 1.0 a minor
release may change settings, binds or file layout; when it does, the migration
that carries an existing install across ships with it (`kuwai migrations`) and
is listed here.

## 0.2.0 — unreleased

### Welcome
- A new install opens Welcome: the four keys that reach nearly everything, and
  clipboard history and GitHub/Gmail notifications to turn on if you want them.
  After an update, the notch says so; a click shows what's new.
- kuwai is an AUR package (`kuwai`): pacman installs everything it needs, and
  `kuwai-setup` sets it up in your home.

### The notch
- Notifications and Controls (with Sound) are the island's own panels, the
  notch grown (the phone's model): going between Agents, Usage, Notifications
  and Controls is one shape changing, and Esc goes back where you came from.
  Waybar and the floating pill keep the corner card.
- Notifications and Controls work at large text sizes: fields and tabs grow,
  control tiles go one to a row, the filters' tools move under them.
- A row you swipe away that has to stay (an agent you only marked read) comes
  back instead of hiding in its slot; a terminal agent is marked read in place.
- Every menu has the same rows, type and surface (the tray's menus too).
- Notifications opens with a Today row (the date, what's next, the weather);
  Controls has a Sound module (the output's volume; right-click mutes).
- Switching island panels and centre tabs crossfades instead of cutting.
- Text is one notch larger on a real scale (11 · 12 · 13 · 14 · 15 · 16 · 19
  · 22 · 26) and panels are 20 px wider; one colour means "on"; capsules
  keep a coloured edge only when something needs you.
- Capsules on the right can be swiped up to hide them until what they say
  changes (it never worked: the screen's edge stopped the pointer short).
- The Agents panel no longer repeats usage; it lives in the Usage section.

### Polish before the announcement
- Keys are named as a PC keyboard prints them (Super, Ctrl, Alt, Shift, Esc, Tab)
  on every cap, hint and footer; the ⌘ ⌥ ⌃ ⇧ glyphs are gone. Welcome's words are
  plainer and its key column grows with Text size.
- One spelling (UK: centre, colour, minimise) and one casing (kuwai) in the
  shell, the docs and the site.
- Usage, Updates, Agents and Cleanup each show one state at a time (loading,
  empty, error or content, never stacked); a failed refresh over a list says so on
  the list's own header or footer with Retry beside it. Orange means "needs you"
  and nothing else (charts and held packages no longer use it).
- Lock and login share one set of tokens for the clock, its line, the hint and
  the password cell; the farewell's moon and door are drawn, like its other marks.
- Clipboard, Lock, Login, Assistant, the volume and brightness HUD and the toasts
  are staged in the rehearsal, in their main states, at every Text size.

### Install and updates
- Rollback undoes migrations. A migration names what it changes in
  `# touches:` lines; the runner copies those paths first, puts them back at
  once if the migration fails, and `kuwai rollback` (and a promote or
  update-self that fails partway) puts them back when returning to a release
  that doesn't have that migration. A path you changed since is kept and named.
  `kuwai migrations --undo N…` does it by hand.
- A fresh Arch install works: the core packages now include what the desktop
  calls at once (awww, pacman-contrib, libpulse and pipewire-pulse, hyprsunset,
  hyprpicker, xdg-utils, polkit, upower, sqlite, and diffutils, which Arch's
  base doesn't have), install.sh refuses a Hyprland older than 0.57, and the
  island is the default bar.
- The stable copy is its own clone, so moving or deleting the folder you
  installed from doesn't break `update-self`, `rollback` or `version`.
- `bin/kuwai-cleanroom` (and a CI job) installs on a fresh Arch container as a
  new user and checks every step through to an uninstall that puts the home
  folder back.
- Screenshots need only grim and slurp (grimblast is gone); recording falls
  back to wf-recorder; an agent opens in whatever terminal you have.

### Motion
- Unlocking gives you the desktop at 400 ms instead of 760: the lock lifts
  with the shackle, not after it, and the release is computed from the tokens.
- Super+V, Super+N and Super+/ each have one entrance: the shelf, the centre
  and the key palette no longer stagger their rows after the panel arrives.
- Closing the island is quicker than opening it, and the clock and capsules
  come back together instead of one after another.
- A working agent's glow breathes slower and shallower, and holds still while
  you're in the panel; an alarm stops swinging while the pointer is on it.
- A toast moves on one curve and finishes fading before it is removed; a
  notification peek fades in once.

### Software Update
- Before you update, it names what pacman adds beyond the list (new
  dependencies, replacements); afterwards it says which steps happened, and a
  run where the Arch update worked but something after it didn't says "Partly
  done" instead of claiming nothing changed.
- Pruning the package cache after updating is a setting, off by default.
- Config files an update left beside yours (.pacnew) are compared with the
  right older version, each file reports how it went, and backups get names of
  their own instead of overwriting one another.
- "Only when you open Software Update" means no checks run by themselves.

### Security
- Release updates (`kuwai update-self`) take only tags that exist on GitHub,
  refuse a tag that moves, and check signatures once you list a signer.
- The password prompt can run from a copy only root can change
  (`kuwai auth pin`).
- Clipboard history and the GitHub/Gmail feeds run only if you said yes
  (`kuwai collect`); installing asks.
- The login screen's installer shows its plan first, installs only committed
  code, and gets only the display settings it needs.
- One rule for secrets covers everything the assistant reads and its sandbox
  log; a terminal's last command goes to it only if you turn that on.
- Ending a process from the launcher can't hit a newer process that reused its
  number; the sandbox never removes a container it didn't make; calendar links
  stay out of process lists and must be HTTPS.
- Allow on an agent's request is bound to that request: the panel shows the
  request's own command in full, and the answer carries its id (kittymux's
  mux-ask ignores any other).
- Notification text keeps only bold, italic, underline and line breaks; an
  image tag, closed or not, can no longer make the shell fetch a URL.
- Package files are copied to a root-only folder before `pacman -U`, so a file
  swapped after the check is never the one installed.
- The assistant: secret-shaped text is removed from what it reads off the
  clipboard and selection; chat mode no longer reads the clipboard or runs the
  system audit; a page is rendered from the bytes already fetched, with the
  browser's network off. The sandbox folder is private to you.
- The login screen never takes code from a folder you can write; a theme
  reinstall keeps the old copy until the new one is in place.

## 0.1.0 — 2026-11-25

The first release. kuwai is a desktop for Arch Linux: its own Hyprland session
(Lua config, Hyprland 0.57 or newer) and its own Quickshell shell, built
around one status surface at the top of the screen, the island.

An earlier `0.2.0` label was written into `VERSION` and this file before
anything was tagged. Nothing was ever released under it, and everything it
listed is part of 0.1.0.

### Install and updates
- `install.sh` with `--dry-run`, `--deps` (packages from `packages/core.txt`,
  `optional.txt`, `fonts.txt`; `--yes` for no prompts), `--doctor` and
  `--uninstall`, which puts back everything it replaced, user services included.
- kuwai is its own login session. Its Hyprland config lives in
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
  carry on), system news and minimised windows (Super+O).
- Agents, Usage, System and Cleanup are sections of one panel, switched from a
  header strip or with Alt+1–4. Every panel works from the keyboard.
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

### Notifications and the centre
- kuwai runs its own notification server, with a Sonner-style toast stack.
  Important notifications peek out of the notch, and apps can offer their own
  buttons there.
- One notification centre (Super+N), with Notifications, Sound (a per-app
  mixer and outputs) and Controls (Wi‑Fi, Bluetooth, DND, Night Shift,
  Caffeine, mic, Reduce Motion, battery, brightness).
- Swipe a notification away and undo a clear. Stale news leaves on its own.
  Chat messages never show on the lock screen.
- One rule decides who may interrupt. An agent asking you reaches you
  everywhere. Under Focus, DND or screen sharing nothing grows the notch.
- GitHub and Gmail feeds (`kuwai feeds`). Bot reviews and failures toast; the
  rest waits in the centre.

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
