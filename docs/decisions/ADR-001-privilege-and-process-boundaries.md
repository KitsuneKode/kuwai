# ADR-001: Separate Privilege and Process Boundaries for Greeter, Polkit Auth, RTC Wake, and Screensaver Film

## Status
Accepted

## Date
2026-11-21

## Context
Four desktop surfaces handle sensitive credentials, root hardware writes, or
heavy video decoder state that must not share address space or write
permissions with the main user shell (`shell/`):

- **Login screen (`greeter/`)**: Runs as `greetd`'s `greeter` user and captures
  the user's login password. It also needs Hyprland to bring up an NVIDIA dGPU
  so external monitors light up at login (GRUB and SDDM only drove the laptop
  panel), while still reflecting the user's wallpaper, theme, monitors, and
  keyboard layout.
- **Polkit password prompt (`shell-auth/`)**: Captures elevation passwords. The
  main shell handles untrusted external content (notifications, clipboard
  previews, web content) and reloads frequently on edits or crashes.
- **Wake alarms (`system/kuwai-wake-root`)**: Writing `/sys/class/rtc/rtc0/wakealarm`
  requires root, while alarms are configured from the user session.
- **Screensaver video (`shell-saver/shell.qml`)**: Measured inside the main
  shell, Qt's video player consumed ~190 MB while playing and retained ~110 MB
  permanently after stopping.

## Decision

1. **Greeter code/data split (`greeter/install`, `greeter/sync`, `greeter/hyprland.lua`, `greeter/start`, `greeter/session-start`, `greeter/keys`)**:
   - Everything executable in `/var/lib/kuwai-greeter` (`shell/`, `hyprland.lua`,
     `start`, `session-start`, `compositor-start`, `keys`) is owned by `root`
     and refreshed only via `sudo greeter/install --code` (with explicit
     `chown -R root:root` because `rsync` preserves prior ownership on unchanged
     files).
   - Only `/var/lib/kuwai-greeter/home/` is user-writable (`greeter/sync` copies
     wallpaper, theme, face, and `kuwai-greeter.conf` as data).
   - `greeter/hyprland.lua` parses `kuwai-greeter.conf` strictly as data (known
     keys, bounded numbers, restricted alphabets, XKB symbol file check,
     monitor description as selector string only) and discards the whole file on
     any invalid line rather than executing user-writable Lua. It matches the
     session's 10-bit depth/colour and NVIDIA-first GPU ordering for a clean
     handoff.
   - `/etc/pam.d/greetd` uses the same PAM stack as SDDM so the login password
     unlocks GNOME Keyring and `gcr-ssh-agent`.
   - `greeter/keys` adjusts only the focused monitor (matching
     `bin/kuwai-brightness`) and serialises slow (~0.3 s) DDC writes, dropping
     queued repeats so held keys never build backlog or drift monitors apart.
   - `greeter/session-start` and `greeter/start` fall back gracefully if
     journald is unavailable so missing logging never blocks login.

2. **Isolated Polkit authentication agent (`shell-auth/shell.qml`, `shell-auth/components/`, `shell-auth/config/Theme.qml`, `bin/kuwai`)**:
   - Runs as a dedicated systemd user unit (`kuwai-auth.service`) with no crash
     handler or core dumps. Exits with code 3 if another agent owns the session
     so systemd falls back to KDE's polkit agent.
   - Components and tokens in `shell-auth/` are reviewed vendored copies — never
     symlinks into `shell/` — enforcing a read-files-and-draw-only rule audited
     by `kuwai doctor` (`auth_audit`).
   - Renders in software mode using plain rectangles (no Canvas, no GPU circle
     clipping — `~/.face` is pre-cropped once by ImageMagick).
   - Password input uses `TextInput.NoEcho` (no per-character dots that leak
     length to onlookers or recordings), displaying a fixed 5-dot pulse wave on
     keystrokes and wiping `field.text` on submit, cancel, and close.
   - Automatically selects the current user when polkit lists multiple admins
     (swallowing the expected PAM-restart failure signal) and queries
     `pam_faillock` read-only for remaining tries.
   - Uses `hyprctl repl 'return kuwai.where()'` to choose the target monitor
     because Quickshell's active screen can be stale, and publishes non-secret
     pending-request metadata (plus PID) to `$XDG_RUNTIME_DIR/kuwai/auth-pending`
     so the island can summon the prompt across monitors.

3. **Data-only RTC wake helper (`system/install`, `system/kuwai-wake-root`)**:
   - The user owns only `/var/lib/kuwai-wake/at` (a single Unix timestamp or `0`).
   - The root-owned helper installed at `/usr/local/libexec/kuwai-wake-root`
     parses strictly one integer bounded to the next 8 days, clears `wakealarm`
     first (the Linux kernel refuses to overwrite an already-set RTC alarm),
     and writes the new value.

4. **Out-of-process screensaver film (`shell-saver/shell.qml`)**:
   - Spawned as a separate Quickshell process on the Top layer (under the main
     shell's Overlay screensaver) with namespace `kuwai.saver-film` outside blur
     rules, and `SIGKILL`ed on dismiss so the OS reclaims 100% of decoder memory.
     Any unexpected exit triggers fallback to Dusk.

## Alternatives Considered

- **Running polkit auth and screensaver video inside the main `shell/` process**:
  Rejected. Untrusted content and shell reloads would share address space with
  passwords, and Qt's video player permanently leaked ~110 MB per screensaver
  cycle inside the long-lived shell.
- **Symlinking `shell-auth/components/` to `shell/components/`**:
  Rejected. Any future edit adding a `Process` or IPC call to a shared shell
  component would silently execute inside the password prompt process.
- **Executing user-writable Lua directly in the greeter**:
  Rejected. Would allow any process running as the user to run arbitrary code in
  the password-capturing greeter context.

## Consequences
- Security audits (`kuwai doctor`) can mechanically verify that `shell-auth/`
  contains no symlinks and no unexpected process/IPC primitives.
- `shell-auth/` vendored copies require deliberate updates when `shell/` tokens
  or components change.
- Screensaver teardown reclaims all video memory immediately at the cost of a
  small process spawn on screensaver activation.
