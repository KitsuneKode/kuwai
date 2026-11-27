# Security and privacy

kuwai runs as your normal user session (Hyprland, Quickshell, systemd user units). No telemetry is sent. Privileged operations are isolated into narrow root-owned helpers, and background data collection is opt-in.

## What runs as root and why

| Component | Installed by | Boundary |
| --- | --- | --- |
| `/usr/local/bin/kuwai-session` and `/usr/share/wayland-sessions/kuwai.desktop` | `sudo system/session` (run once by `install.sh`; `--undo` removes) | Registers the **Kuwai** Wayland session entry |
| `/usr/local/share/kuwai/shell-auth/` | `kuwai auth pin` (run once by `install.sh`; `unpin` removes) | Root-owned copy of the standalone polkit password prompt (`kuwai-auth.service`). Uses vendored components (no symlinks to `shell/`), software rendering, no core dumps, and `TextInput.NoEcho` (five-dot pulse so password length is never revealed). The island only trusts prompts from `/usr/bin/qs` running the pinned/stable path in the `kuwai-auth.service` cgroup |
| `/usr/local/lib/kuwai/kuwai-update-root` | `kuwai update install-helper` | Started on demand via `pkexec` with the allowed operations named in `argv` (`upgrade`, `deps`, `install`, `pacnew`, `clean-cache`). Runs `pacman` and `paccache` only; copies built AUR packages without following symlinks into a root-only directory and checks their `sha256` before `pacman -U`; refuses automatic `.pacnew` replacement on `passwd`, `shadow`, `group`, `gshadow`, `fstab`, and `crypttab`; validates sudoers with `visudo -c` |
| `/var/lib/kuwai-greeter/` (optional) | `sudo greeter/install` (`--code` updates; `--undo` restores previous DM) | Installs committed `shell/` and `greeter/` files owned by root (links refused). Your user can write only `/var/lib/kuwai-greeter/home/` (wallpaper, colours, face, and plain monitor/keyboard data validated line-by-line by `greeter/hyprland.lua`) |
| `/usr/local/libexec/kuwai-wake-root` (optional) | `sudo system/install` (`--undo` removes) | Reads one bounded Unix timestamp (next 8 days max) from `/var/lib/kuwai-wake/at` and writes `/sys/class/rtc/rtc0/wakealarm` |

## What is collected and where it stays

- **Clipboard history (`kuwai-clipboard.service`):** off by default until enabled during install or with `kuwai collect clipboard on`. Stored locally by `cliphist` and `~/.local/share/kuwai`.
- **GitHub and Gmail feeds (`kuwai-feeds.service`):** off by default (`kuwai collect feeds on`). GitHub uses your `gh` login; Gmail uses an app password kept in the system keyring (`secret-tool`). State lives in `~/.local/state/kuwai/feeds.json`.
- **Local assistant:** off by default (`Settings → Assistant`). Secret-shaped text is redacted from clipboard/selection reads and sandbox logs; file reads and searches share one exclusion policy.
- **Permissions on disk:** `~/.config/kuwai`, `~/.local/state/kuwai`, and `~/.cache/kuwai` are kept mode `0700`. T3 Code tokens (`t3-token`, `t3-operate-token`) are ignored if group/world-readable and can be stored in the system keyring instead.

## Hardening enforced by tests

- **Untrusted text (`tests/security/test_text_format.py`):** external strings (titles, notification text, tool output) render as `Text.PlainText` or sanitized markup with no remote `<img>` fetches.
- **Links (`tests/security/test_links.py`):** opened links pass through `Links.safeLink` (web and mail schemes only).
- **Commands:** values are passed as `argv`, never interpolated into shell strings; process termination from the launcher checks process identity so reused PIDs cannot be hit.
- **Releases (`tests/recovery/test_release_refs.py`):** `kuwai update-self` fetches only `v*` release tags from `origin`, verifies signatures against `release-signers`, and refuses any tag whose target commit moves after first sight.
- **Root helper and installer (`tests/root/`, `tests/install/`):** hostile paths, `..` traversal, and symlinks are refused before touching files; uninstall restores pre-install state.

## Known limitations and accepted boundaries

- **Same-user trust boundary:** `VoxtypeHost` loads voxtype QML from `$XDG_DATA_HOME/voxtype/quickshell` when voxtype is installed, and `kuwai-auth.service` is a user unit. Both run under the same user account as the main shell; pinning `shell-auth/` via `kuwai auth pin` protects the prompt code itself.
- **Not yet formally qualified across all hardware:** live lock-screen failure recovery on every GPU/compositor crash mode, portal screen-share blackouts across all compositor/app combinations, and an independent audit of the optional Ollama assistant's tool execution.
- **Full-disk encryption:** kuwai does not replace OS-level disk encryption.

Report vulnerabilities privately as described in [SECURITY.md](../../SECURITY.md).
