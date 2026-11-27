# Install, updates, and uninstall

## Requirements

- **Arch Linux** with systemd user sessions.
- **Hyprland 0.57 or newer** (Lua configuration). `install.sh` refuses older versions.
- **Core packages** listed in [packages/core.txt](../../packages/core.txt) and fonts in [packages/fonts.txt](../../packages/fonts.txt) (`inter-font`, `ttf-nerd-fonts-symbols`).
- **Optional packages** in [packages/optional.txt](../../packages/optional.txt) add screenshot annotation (`satty`), OCR (`tesseract`), live wallpapers (`mpv`, `mpvpaper`), external monitor brightness (`ddcutil`), Wi-Fi (`networkmanager`), Bluetooth (`bluez-utils`), GitHub/Gmail feeds (`github-cli`, `libsecret`), Cleanup (`ripgrep`), and fallback bar/lock (`waybar`, `hyprlock`, `hypridle`).

## Installing a signed release

```sh
git clone https://github.com/KitsuneKode/kuwai.git ~/Projects/kuwai
~/Projects/kuwai/bin/kuwai-setup --verify-only   # fetch and check the newest release; install nothing
~/Projects/kuwai/bin/kuwai-setup --deps          # check it, give root a checked copy, install it for you
```

The clone only provides `kuwai-setup` and the release keys; what gets installed is the release `kuwai-setup` checked:

1. It picks the newest `vX.Y.Z` tag at `--source` (GitHub by default), or `--tag vX.Y.Z`.
2. It fetches only that tag into a new folder of its own under `~/.cache/kuwai/releases`.
3. It checks the tag before anything in it runs: `git verify-tag` against a keyring built from `release-signers/*.asc` alone, in a temporary `GNUPGHOME`; the tag's own name; and `kuwai-tree-sha256`, the digest of every file in the tree, which the signature covers. After checking out it compares the files on disk with that digest again.
4. Root's copy (`sudo`, once): `/usr/local/lib/kuwai/releases/vX.Y.Z`, owned by root. Root checks its copy again with `gpgv` against the fingerprints it keeps and the digest of every file, with its own `kuwai-verify` once it has a release. `kuwai-setup` names the release keys to root only at the first install; after that root takes its keys from each release a key it already trusts signed (how a key changes: [release-signers/README](../../release-signers/README)). If root refuses the release, nothing is installed. Without a terminal for `sudo`, `kuwai-setup` prints this command for later.
5. It runs that release's `install.sh` as you. Options it doesn't know go there.

It prints the fingerprint of the key that signed the release; the release key is `7C78 CB85 5D50 4BDF 3E9B 74AF F150 E88B 5072 0270`. An unsigned tag, a tag signed by any other key, a tag without the digest or with another tree's, or a tag renamed from another release is refused, and nothing from it runs. While `release-signers/` holds no key, every release is refused.

`kuwai-setup --system` only brings root's copy to a release (after `kuwai update-self`, which says when root's copy is behind).

Developing kuwai: `./install.sh` in a clone installs that clone for you (`--dry-run` previews it). The root scripts refuse to run from a clone unless given `--trust-clone`, which says that it trusts every file in it.

Useful `install.sh` flags (also accepted by `kuwai-setup`):

- `--deps`: install missing core packages and fonts via `sudo pacman -S --needed` (add `--yes` for `--noconfirm`).
- `--print-missing`: list missing core packages and fonts one per line and exit.
- `--no-services`: skip linking and enabling systemd user units.
- `--clipboard` / `--no-clipboard`: pre-answer whether to enable `kuwai-clipboard.service`.
- `--feeds` / `--no-feeds`: pre-answer whether to enable `kuwai-feeds.service`.
- `--separate-session`: migrate an older install that used `~/.config/hypr/hyprland.lua` into `~/.config/kuwai/hypr/`.
- `--doctor`: check dependencies and run `kuwai doctor`.

What `install.sh` puts in place:

1. Clones the `stable` branch into `~/.local/share/kuwai` (independent of your working clone).
2. Records the original state of every file and user unit it replaces under `~/.local/state/kuwai/original/`.
3. Writes `~/.config/kuwai/hypr/hyprland.lua` and creates empty `monitors.lua` and `user.lua` beside it if missing (never overwritten). `~/.config/hypr` is untouched.
4. Symlinks `~/.local/bin/kuwai` to `~/.local/share/kuwai/bin/kuwai`.
5. Links user systemd units (`kuwai-shell.service`, `kuwai-shell-broken.service`, `kuwai-auth.service`, `kuwai-wallpaper.service`, `kuwai-backup.service`, `kuwai-backup.timer`, plus opt-in `kuwai-clipboard.service` and `kuwai-feeds.service`).
6. Installs the **kuwai** login session entry (`sudo /usr/local/lib/kuwai/current/system/session`) and pins the polkit password prompt (`kuwai auth pin`) from root's checked copy when run interactively; without that copy it says how to get it.
7. Downloads the first wallpaper from `themes/kuwai-night/wallpapers.tsv` (verified by checksum) when no wallpaper or HyDE setup is present.

Log out and choose **kuwai** on your display manager, or start it from a TTY with `kuwai-session`.

## AUR package

`packaging/aur/kuwai/PKGBUILD` builds from the signed release tag (`?signed`, checked by makepkg against `validpgpkeys`) and installs that tag's `kuwai-setup`, `kuwai-verify` and `release-signers/` under `/usr/lib/kuwai`, with `/usr/bin/kuwai-setup`. Installing the package installs the Arch dependencies through `pacman`; running `kuwai-setup` as your normal user does everything above.

## Optional root integrations

All of them run only from root's checked copy, check it again first, and are reversible with `--undo`:

```sh
sudo /usr/local/lib/kuwai/current/greeter/install   # greetd login screen (--code updates its root copy; --undo restores the previous login)
sudo /usr/local/lib/kuwai/current/system/install    # kuwai-wake RTC alarm wake helper (--undo removes it)
kuwai update install-helper                          # /usr/local/lib/kuwai/kuwai-update-root for Software Update, from root's copy (--trust-clone: from your clone, before root has a release)
sudo greeter/install          # greetd login screen (--code updates its root copy; --undo restores previous DM)
sudo system/install           # kuwai-wake RTC alarm wake helper (--undo removes it)
kuwai update install-helper   # installs /usr/local/lib/kuwai/kuwai-update-root for Software Update
sudo system/plymouth/install  # boot splash theme (see boot.md; --dry-run first, --undo removes it)
```

`greeter/install` writes a receipt the first time (`/var/lib/kuwai-greeter/original/receipt`, root's, `0600`): the files it replaced, the digest of each kept copy, and the login manager that was on. `--undo` restores only what that receipt lists, from copies that still match it. An install from before receipts has none: `--undo` then records what is kept, but only when every folder down to the kept copies, and each copy, is root's alone; otherwise it restores nothing.

## Channels, releases, and updates

Your live desktop runs from `~/.local/share/kuwai` (the **stable** channel).

| Command | What it does |
| --- | --- |
| `kuwai version` | Prints `VERSION`, the commit `stable` runs, and the active channel |
| `kuwai update-self` | Fetches the newest `v*` release tag from `origin`, checks it as `kuwai-setup` does (signed by a key in the running release's `release-signers/`, or yours in `~/.config/kuwai/release-signers/`; every file the signed one) and against local `release-pins`, checks Lua syntax, runs offscreen load tests for `shell.qml` and `greeter.qml`, fast-forwards `stable`, runs migrations, and restarts the shell (rolling back automatically if startup fails) |
| `kuwai update-self --ref REF` | Follows an explicit git ref (unsigned, for testing; `KUWAI_UPDATE_REF` is ignored) |
| `kuwai rollback` | Reverts `stable` to `stable-prev`, undoing migrations introduced after that commit. Rolling forward again runs that release's migrations first; if one fails, stable stays where it was and nothing restarts |
| `kuwai channel [stable\|dev]` | Show or switch whether `kuwai-shell.service` runs `~/.local/share/kuwai` or your dev checkout |
| `kuwai promote` | Validates dev `HEAD` (`kuwai-check`, backup, `qmllint`, `pdeathsig` check, Lua parse, load tests, migration check) and fast-forwards `stable` |
| `kuwai migrations` | Lists, runs, or undoes (`--undo N`) state/config migrations |
| `kuwai backup` | Snapshots user config/state files; supports diff and restore |
| `kuwai export [FILE]` | Exports a portable machine manifest (packages, monitors, settings; no secrets) |
| `kuwai release vX.Y.Z` | Maintainer command: `git tag -s` on `main` with your OpenPGP key from `release-signers/` (`KUWAI_RELEASE_KEY=FINGERPRINT` to choose), the tree's `kuwai-tree-sha256` in the message; checks the tag the way an install will and deletes it if that fails ([release-signers/README](../../release-signers/README)) |

## Uninstalling

```sh
./install.sh --uninstall
```

This restores the files and systemd unit states captured before the first install. Your `~/.config/kuwai` settings and notes are kept. To remove the remaining pieces completely:

```sh
rm -rf ~/.local/share/kuwai
sudo /usr/local/lib/kuwai/current/system/session --undo
kuwai auth unpin
sudo /usr/local/lib/kuwai/current/greeter/install --undo   # if installed
sudo /usr/local/lib/kuwai/current/system/install --undo    # if installed
sudo rm -rf /usr/local/lib/kuwai                            # root's copy, last
```
