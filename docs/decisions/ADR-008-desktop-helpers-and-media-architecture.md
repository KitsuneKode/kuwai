# ADR-008: Desktop Helpers Architecture (Brightness, Clipboard, Feeds, Media, and Usage/Spend)

## Status
Accepted

## Date
2026-11-21

## Context
kuwai delegates hardware, clipboard, feed, media, screenshot, and telemetry
work to focused CLI helpers under `bin/` and `lib/`. Each helper evolved to
solve concrete desktop failure modes:

- A detached brightness daemon started from a dev checkout kept serving the
  promoted desktop for 46 hours after exit/promote because nothing checked
  which code copy owned the socket.
- Wayland clears the clipboard when the copying window closes (especially
  drop-down terminals); `grimblast` left `wl-copy` holding stderr pipes open;
  deleting clipboard entries previously left decoded images and render caches
  behind on disk; `find` failing on a missing cache subdir aborted `kuwai-clip`
  under `set -e`.
- A shared D-Bus notification callback queue in `kuwai-feeds` desynchronized
  actions across every subsequent notification whenever a shell restart dropped
  one call; launching a browser inside `kuwai-feeds`'s cgroup pinned 2.5 GB to
  the service and killed the browser on service restart; advancing feed
  watermarks before handling lost items on transient failures.
- `mpvpaper` read `~/.config/mpv` (loading shaders, scripts, Vulkan, and a
  256 MiB cache per monitor for background wallpaper loops); `ffmpeg`'s `xfade`
  renegotiated 4:4:4 sources back to `yuv444p` (undecodable on GPU).
- Reading 512 MB+ agent session logs whole caused high memory spikes; running
  `kuwai-usage` under `node` cost 11–29 MB private RSS vs ~4 MB under `bun`.

## Decision

1. **Session-owned brightness controller (`lib/brightness/brightness.py`, `brightness-client.py`, `bin/kuwai-brightness`)**:
   - Single detached controller per session recording its code identity (file
     path + hash) in `runtime/owner`. Clients from the session's `KUWAI_ROOT`
     replace mismatched/older controllers; clients from other checkouts or
     tests use the existing controller without hijacking it.
   - Unified brightness curve across laptop backlight and DDC monitors (1%
     steps below 10%, snapped to 5% grid above), 8-step eased DDC ramps,
     invalidating I2C bus mappings before hotplug discovery (bus numbers are
     not stable output IDs), passive kernel uevents (no polling), and explicit
     watcher teardown on shutdown (Python 3.12+ server context exit waits for
     open clients).

2. **Clipboard, screenshots, and screen recording (`bin/kuwai-clip`, `bin/kuwai-shot`, `bin/kuwai-rec`, `hypr/kuwai/startup.lua`)**:
   - Run `wl-clip-persist` so copies outlive closed windows; keep clipboard
     history in `cliphist` and long-lived pins separately; bound temp open/edit
     caches with non-fatal cleanup (`|| true`); delete decoded images and
     render caches on entry deletion/wipe.
   - In `kuwai-shot`, treat drags under 16 px as window clicks, mask window
     captures to the window's actual Hyprland rounding/squircle power (unless
     fullscreen), redirect `grimblast` stderr to a temp file instead of a pipe
     (so background `wl-copy` cannot hang capture), and omit Satty's bare
     `--early-exit` so copying keeps the editor open.
   - In `kuwai-rec`, stop GPU Screen Recorder with `SIGINT` (cleanly finalizes
     the container) and emit a thumbnail frame for the island toast.

3. **Feeds, notifications, and Cider (`bin/kuwai-feeds`, `bin/kuwai-notify`, `bin/kuwai-player`)**:
   - Bind each notification's `(key, handlers)` directly to its D-Bus call
     callback (never a shared FIFO queue); launch URLs via
     `systemd-run --user --collect --slice=app.slice` after checking
     `https?://`; restrict GitHub avatars to `avatars.githubusercontent.com`
     (≤1 MB); advance GitHub/Gmail watermarks strictly after an item is
     handled (stopping before failures so nothing is skipped or duplicated);
     renew Gmail IDLE every 24 minutes (before Gmail's ~30 min drop).
   - `bin/kuwai-notify` talks directly to `org.freedesktop.Notifications` via
     `gdbus` (avoiding broken host `libnotify` / `LD_LIBRARY_PATH` leaks).
   - `bin/kuwai-player` stores Cider's local API token in the keyring and
     passes it to `curl` via header FD (`@<(...)`), never argv or disk.

4. **Live wallpapers, usage/spend, process listing, and UI testing (`bin/kuwai-livewall`, `bin/kuwai-wall`, `bin/kuwai-usage`, `bin/kuwai-spend`, `lib/spend.mjs`, `bin/kuwai-procs`, `bin/kuwai-rehearse`, `lib/rehearse/`, `bin/kuwai-ui-test`)**:
   - Isolate `mpvpaper` with its own minimal `mpvpaper-home` config; cap
     imported/added live wallpapers at 1440p and force `-pix_fmt yuv420p`
     *after* `xfade` so GPUs can hardware-decode every loop.
   - `bin/kuwai-usage` reads T3 Code's local WebSocket RPC (`server.getConfig`
     / `subscribeServerConfig`) with a read-only `0600` token sent only in the
     `Authorization` header, prefers `bun` (~4 MB private RSS), and caches the
     last T3 snapshot owner-only so rings remain accurate while T3 is closed.
   - `bin/kuwai-spend` + `lib/spend.mjs` read agent logs incrementally by byte
     offset in 8 MB chunks (skipping >64 MB lines), keeping 35 days and
     deduplicating Claude's multi-block assistant entries by message ID.
   - `bin/kuwai-procs` samples `/proc` over 0.6 s with a 10% CPU busy threshold
     and restricts full-cmdline matching to 4+ character queries.
   - `bin/kuwai-rehearse` + `lib/rehearse/` enforce WCAG 2.2 minimum target
     size (24 px) and contrast (4.5:1 normal, 3:1 large); `bin/kuwai-ui-test`
     runs offscreen scenes in isolated net/home namespaces with real
     `kuwai-settings`, stubbing only layer-shell adapters (`Caffeine.qml`,
     `WallFx.qml`) and failing on teardown crashes.

## Alternatives Considered

- **Polling brightness/usage/feeds on short intervals**:
  Rejected in favor of kernel uevents, WebSocket push (`subscribeServerConfig`),
  and IMAP IDLE to keep idle CPU near zero.
- **Sharing `~/.config/mpv` with `mpvpaper`**:
  Rejected because high-end cinema shaders and 256 MiB caches multiplied per
  monitor made background loops prohibitively expensive.

## Consequences
- Helpers remain small, composable, and testable independently of the live
  Wayland session.
- Any new helper interacting with user secrets or external URLs must follow the
  same keyring/FD and URL-allowlist conventions.
