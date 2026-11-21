# ADR-005: Stable/Dev Channels, Promotion Safety Gates, Backups, and Landlock-Fenced Migrations

## Status
Accepted

## Date
2026-11-21

## Context
The live desktop shell hot-reloads when files under `shell/` change. Editing
directly in the live checkout risks breaking the desktop mid-edit, while
unvalidated promotions have previously broken the desktop via dangling QML IDs,
`FINAL` property overrides, leaked streaming helpers (127 helpers + 78 polling
loops = 1.1 GB RAM), dirty worktree resets, or mismatched user state across
updates.

## Decision

1. **Two-channel layout (`hypr/templates/hyprland.lua`, `bin/kuwai-ctl`, `hypr/kuwai/env.lua`)**:
   - `stable` runs from a dedicated git worktree of the `stable` branch at
     `~/.local/share/kuwai`; `dev` runs from the working repository.
   - `~/.local/state/kuwai/channel` takes precedence over inherited
     `$KUWAI_ROOT` so Hyprland reloads switch channels cleanly, and `env.lua`
     strips the inactive channel's `bin/` from `PATH` while deduplicating `PATH`
     across reloads.
   - `hypr/templates/hyprland.lua` includes a minimal fallback keymap if kuwai
     fails to load so the user keeps a terminal, workspaces, and exit control.

2. **Promotion safety gates and automatic rollback (`bin/kuwai-ctl`, `bin/kuwai-loadtest`, `bin/kuwai-check`)**:
   - `kuwai promote` is fast-forward only and refuses to run if the `stable`
     worktree is dirty (preventing hard-reset loss of direct edits).
   - Pre-promote gates: live health (`bin/kuwai-check`), automatic backup
     (`bin/kuwai-backup auto`), `qmllint` on changed QML, `setpriv --pdeathsig`
     check on all streaming helpers, `luac -p` on all Lua (since offline
     `Hyprland --verify-config` crashes on 0.57 and executes `exec` lines),
     offscreen Quickshell load test (`bin/kuwai-loadtest`, failing closed unless
     the error chain terminates at the exact expected
     `"No PanelWindow backend loaded"` stop), and `bin/kuwai-migrations --check`.
   - After moving `stable`, pending migrations run before the new shell starts;
     any migration failure, new Hyprland config errors, or live shell load
     failure automatically rolls `stable` back to the prior commit (after
     stopping any `kuwai-shell-watch` retry matched by exact `argv[3]`, never
     a broad pattern).
   - `bin/kuwai-check` waits 15 s after shell startup before measuring CPU,
     uses the median of five 1-second samples (eliminating ~25% single-window
     flake rate from notifications/polls), and runs per-file QML `compile` after
     memory/CPU checks because compiling caches types in memory.

3. **Landlock-fenced one-time migrations (`bin/kuwai-migrations`, `migrations/`)**:
   - Ordered `NNNN-name.sh` scripts run once per machine under `bash -euo pipefail`,
     never as root, with a 5-minute timeout and Linux Landlock via `setpriv`
     permitting writes exclusively inside the four XDG directories under `$HOME`
     (plus `/dev/null`).
   - Fails closed (exit 2) when Landlock/`setpriv` is unavailable, an XDG path
     escapes `$HOME`, or the pre-rename `rice → kuwai` mover (`bin/kuwai-migrate`)
     has not run yet (otherwise migrations would see empty folders and falsely
     mark themselves done).

4. **Lossless install/uninstall and owner-only backups (`install.sh`, `bin/kuwai_install.py`, `bin/kuwai-backup`, `bin/kuwai-shell`)**:
   - `install.sh` records each target path's pre-install state once, replaces
     paths via single atomic rename (replacing symlinks rather than writing
     through them), and defers `systemctl --user enable` when no user bus is
     active (TTY/SSH/container installs).
   - `bin/kuwai-backup` stores owner-only (`0700`) tarballs keeping the newest
     30, fingerprints content to skip unchanged auto-snapshots, and refuses
     symlinks in backup or restore scope.
   - `bin/kuwai-shell` enforces `0700` on kuwai's state, cache, and config
     directories so notification bodies, chats, thumbnails, and tokens stay
     private regardless of umask.

## Alternatives Considered

- **Promoting without pre-checks or relying solely on `qmllint`**:
  Rejected because `qmllint` missed `FINAL` property overrides and duplicate
  handlers that crashed the live shell.
- **Running migrations unfenced**:
  Rejected because a buggy migration script could modify arbitrary files outside
  kuwai's XDG state.

## Consequences
- Promoting to `stable` requires clean git state, Landlock support, and passing
  health/load checks, making live desktop breakage rare and self-reverting.
- Tests and dev checkouts never corrupt the promoted desktop.
