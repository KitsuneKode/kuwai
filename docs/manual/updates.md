# Updates: system packages and kuwai releases

kuwai separates **system package updates** (`Software Update`, `kuwai-update`) from **kuwai self-updates** (`kuwai update-self`).

## System package updates (`Super+Ctrl+Shift+U`)

Open **Software Update** from the island's update chip, the launcher, or `Super+Ctrl+Shift+U`.

### How it runs

1. **Check (`kuwai-update check`):** lists official Arch repository updates (`checkupdates`), AUR updates, optional Flatpak updates, recent Arch Linux news, free disk space, and power state. Setting `Settings → Software Update → Check every` to **Never** (`0`) disables automatic background checks.
2. **AUR review (`kuwai-update review PKG`):** before any AUR package builds, Software Update shows the git diff of its `PKGBUILD` and build files since the version currently installed, flagging suspicious lines. Approving pins the exact 40-character git commit SHA (`~/.local/state/kuwai/aur-approved.json`). If upstream changes after review, the build refuses to run. You can explicitly trust a package (`kuwai-update trust PKG on`) or opt into auto-approving routine version bumps for established AUR packages in Settings.
3. **Detached execution (`kuwai-update start`):** runs inside its own systemd user unit (`kuwai-update`) with sleep and shutdown inhibited, streaming progress to `$XDG_RUNTIME_DIR/kuwai/update.jsonl` and full logs to `~/.local/state/kuwai/updates/`. Restarting the shell does not interrupt pacman.
4. **Atomic Arch upgrade + unprivileged AUR build:** official packages upgrade together with `pacman -Syu` (no partial upgrades). AUR packages build as your user via `makepkg` under `~/.local/share/kuwai-data/aur/` and install together with `pacman -U`.
5. **Post-update checks:** flags if the running kernel differs from installed modules (restart needed) and lists `.pacnew` config files with diffs.

### Root helper (`kuwai-update-root`)

Run `kuwai update install-helper` once to install `/usr/local/lib/kuwai/kuwai-update-root` owned by root. From then on, `kuwai-update` invokes it through `pkexec` naming the exact operations allowed for that run (`upgrade`, `deps`, `install`, `pacnew`, `clean-cache`).

- Built AUR `.pkg.tar.*` files are copied without following symlinks into a root-only temporary directory and checked against their build-time `sha256` before `pacman -U`.
- Replacing `/etc/<file>` with `<file>.pacnew` saves a timestamped backup under `/var/lib/kuwai/pacnew-backups/` and validates sudoers with `visudo -c`.
- Automatic `.pacnew` replacement is **refused** for `passwd`, `shadow`, `group`, `gshadow`, `fstab`, and `crypttab` — merge those manually with `pacdiff`.

### Holds and cache cleanup

```sh
kuwai-update hold PKG          # pass --ignore PKG on future updates
kuwai-update unhold PKG        # remove hold
kuwai-update storage           # show disk usage of update caches
kuwai-update clean --dry-run   # preview cache reclamation
```

Post-update `pacman` cache pruning is configurable in `Settings → Software Update` and off by default.

### If an update says "stopped before finishing"

This happens when the job ended before writing a `done` event (cancelled password prompt, crash, or interrupted run). Inspect the newest log in `~/.local/state/kuwai/updates/` and re-run. If a repo upgrade succeeded but a later step failed, Software Update reports **Partly done** and names which steps completed.

## Updating kuwai itself

```sh
kuwai version          # current version, stable commit, and channel
kuwai update-self      # move stable to the newest signed v* tag
kuwai rollback         # revert stable to stable-prev and undo its migrations
```

See [install.md](install.md) for details on release-tag signature verification (`release-signers`), `kuwai promote`, and `kuwai migrations`.
