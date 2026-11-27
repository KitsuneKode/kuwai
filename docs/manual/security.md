# Security and privacy

kuwai runs as your normal user session (Hyprland, Quickshell, systemd user units). No telemetry is sent. Privileged operations are isolated into narrow root-owned helpers, and background data collection is opt-in.

## What runs as root and why

| Component | Installed by | Boundary |
| --- | --- | --- |
| `/usr/local/lib/kuwai/releases/vX.Y.Z`, `…/signers` | `kuwai-setup` (`sudo`, once per release) | Root's own copy of a signed release, checked by root with `gpgv` against the fingerprints it keeps and the digest of every file. Every piece below is installed from it, and it is checked again each time |
| `/usr/local/bin/kuwai-session` and `/usr/share/wayland-sessions/kuwai.desktop` | `sudo …/current/system/session` (run once by `install.sh`; `--undo` removes) | Registers the **Kuwai** Wayland session entry |
| `/usr/local/share/kuwai/shell-auth/` | `kuwai auth pin` (run once by `install.sh`; `unpin` removes) | Root-owned copy of the standalone polkit password prompt (`kuwai-auth.service`). Uses vendored components (no symlinks to `shell/`), software rendering, no core dumps, and `TextInput.NoEcho` (five-dot pulse so password length is never revealed). The island only trusts prompts from `/usr/bin/qs` running the pinned/stable path in the `kuwai-auth.service` cgroup |
| `/usr/local/lib/kuwai/kuwai-update-root` | `kuwai update install-helper` | Started on demand via `pkexec` with the whole transaction in `argv`, so the password prompt shows it: `upgrade=N:SHA256` (how many Arch packages and the digest of exactly which versions), `hold=`, `deps=`, `install=` (AUR packages by name), `clean-cache=`, `pacnew`. Each runs once; anything else is refused, and a repo upgrade that resolves differently after the sync installs nothing. Runs `pacman` and `paccache` only; copies built AUR packages without following symlinks into a root-only directory and checks their `sha256` before `pacman -U`; refuses automatic `.pacnew` replacement on `passwd`, `shadow`, `group`, `gshadow`, `fstab`, and `crypttab`; validates sudoers with `visudo -c` |
| `/var/lib/kuwai-greeter/` (optional) | `sudo …/current/greeter/install` (`--code` updates; `--undo` restores what its root-owned receipt lists) | Installs root's checked `shell/` and `greeter/` files owned by root (links refused). Your user can write only `/var/lib/kuwai-greeter/home/` (wallpaper, colours, face, and plain monitor/keyboard data validated line-by-line by `greeter/hyprland.lua`) |
| `/usr/local/libexec/kuwai-wake-root` (optional) | `sudo …/current/system/install` (`--undo` removes) | Reads one bounded Unix timestamp (next 8 days max) from `/var/lib/kuwai-wake/at` and writes `/sys/class/rtc/rtc0/wakealarm` |

## What is collected and where it stays

- **Clipboard history (`kuwai-clipboard.service`):** off by default until enabled during install or with `kuwai collect clipboard on`. Stored locally by `cliphist` and `~/.local/share/kuwai`.
- **GitHub and Gmail feeds (`kuwai-feeds.service`):** off by default (`kuwai collect feeds on`). GitHub uses your `gh` login; Gmail uses an app password kept in the system keyring (`secret-tool`). State lives in `~/.local/state/kuwai/feeds.json`.
- **Local assistant:** off by default (`Settings → Assistant`). Secret-shaped text is redacted from clipboard/selection reads and sandbox logs; file reads and searches share one exclusion policy.
- **Permissions on disk:** `~/.config/kuwai`, `~/.local/state/kuwai`, and `~/.cache/kuwai` are kept mode `0700`. T3 Code tokens (`t3-token`, `t3-operate-token`) are ignored if group/world-readable and can be stored in the system keyring instead.

## Hardening enforced by tests

- **Untrusted text (`tests/security/test_text_format.py`):** external strings (titles, notification text, tool output) render as `Text.PlainText` or sanitized markup with no remote `<img>` fetches.
- **Links (`tests/security/test_links.py`):** opened links pass through `Links.safeLink` (web and mail schemes only).
- **Commands:** values are passed as `argv`, never interpolated into shell strings; process termination from the launcher checks process identity so reused PIDs cannot be hit.
- **Releases (`tests/release/`, `tests/recovery/test_release_refs.py`):** `kuwai-setup` and `kuwai update-self` take only a `v*` tag signed by a key in `release-signers/` (a keyring of those keys alone, in a temporary `GNUPGHOME`) whose every file matches the signed `kuwai-tree-sha256`, and run nothing from it before that; `update-self` also refuses any tag whose target commit moves after first sight. Unsigned tags, plain tags, other keys, a missing or wrong digest, a renamed tag, and an empty `release-signers/` are each refused.
- **Root's copy (`tests/release/test_root_copy.py`):** root copies the checked release, then checks its own copy (`gpgv` against the fingerprints it keeps, every file's digest); a file changed after the check, a swapped tag, an untrusted key, an older release, a name with a control character, or a link out of the tree installs nothing. Root's keys change only through releases: one signed by a trusted key that adds a key, then one signed by the new key that drops the old; a tag signed by the dropped key is refused. The root scripts refuse a clone without `--trust-clone`.
- **Update prompt (`tests/root/test_update_root.py`):** the helper runs only the transaction named on its command line; a package set that changes between the prompt and the run is refused before anything is installed.
- **Login screen undo (`tests/greeter/test_receipt.py`):** restores only what the root-owned receipt lists, from kept copies that still match it.
- **Root helper and installer (`tests/root/`, `tests/install/`):** hostile paths, `..` traversal, and symlinks are refused before touching files; uninstall restores pre-install state.

## Known limitations and accepted boundaries

- **Same-user trust boundary:** `VoxtypeHost` loads voxtype QML from `$XDG_DATA_HOME/voxtype/quickshell` when voxtype is installed, and `kuwai-auth.service` is a user unit. Both run under the same user account as the main shell; pinning `shell-auth/` via `kuwai auth pin` protects the prompt code itself.
- **The first install trusts `kuwai-setup` itself:** it comes from your clone (or the AUR package, which makepkg checked against the release key). Check the fingerprint it prints against the published one.
- **Not yet formally qualified across all hardware:** live lock-screen failure recovery on every GPU/compositor crash mode, portal screen-share blackouts across all compositor/app combinations, and an independent audit of the optional Ollama assistant's tool execution.
- **Full-disk encryption:** kuwai does not replace OS-level disk encryption.

Report vulnerabilities privately as described in [SECURITY.md](../../SECURITY.md).
