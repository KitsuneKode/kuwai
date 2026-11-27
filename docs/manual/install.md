# Install, updates, and uninstall

## Requirements

- **Arch Linux** with systemd user sessions.
- **Hyprland 0.57 or newer** (Lua configuration). `install.sh` refuses older versions.
- **Core packages** listed in [packages/core.txt](../../packages/core.txt) and fonts in [packages/fonts.txt](../../packages/fonts.txt) (`inter-font`, `ttf-nerd-fonts-symbols`).
- **Optional packages** in [packages/optional.txt](../../packages/optional.txt) add screenshot annotation (`satty`), OCR (`tesseract`), live wallpapers (`mpv`, `mpvpaper`), external monitor brightness (`ddcutil`), Wi-Fi (`networkmanager`), Bluetooth (`bluez-utils`), GitHub/Gmail feeds (`github-cli`, `libsecret`), Cleanup (`ripgrep`), and fallback bar/lock (`waybar`, `hyprlock`, `hypridle`).

## Installing from git

```sh
git clone https://github.com/KitsuneKode/kuwai.git ~/Projects/kuwai
cd ~/Projects/kuwai
./install.sh --dry-run   # preview changes without modifying anything
./install.sh --deps      # install missing packages and configure kuwai
```

Useful `install.sh` flags:

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
6. Installs the **kuwai** login session entry (`sudo system/session`) and pins the polkit password prompt (`kuwai auth pin`) when run interactively.
7. Downloads the first wallpaper from `themes/kuwai-night/wallpapers.tsv` (verified by checksum) when no wallpaper or HyDE setup is present.

Log out and choose **kuwai** on your display manager, or start it from a TTY with `kuwai-session`.

## AUR package wrapper

`packaging/aur/kuwai/` contains a `PKGBUILD` and `kuwai-setup` script. Installing the package installs the Arch dependencies through `pacman`; running `kuwai-setup` as your normal user clones the matching release tag into `~/.local/share/kuwai-src` and runs `install.sh`.

## Optional root integrations

All optional system helpers are reversible with `--undo`:

```sh
sudo greeter/install          # greetd login screen (--code updates its root copy; --undo restores previous DM)
sudo system/install           # kuwai-wake RTC alarm wake helper (--undo removes it)
kuwai update install-helper   # installs /usr/local/lib/kuwai/kuwai-update-root for Software Update
```

## Channels, releases, and updates

Your live desktop runs from `~/.local/share/kuwai` (the **stable** channel).

| Command | What it does |
| --- | --- |
| `kuwai version` | Prints `VERSION`, the commit `stable` runs, and the active channel |
| `kuwai update-self` | Fetches the newest `v*` release tag from `origin`, verifies its signature against `release-signers` and local `release-pins`, checks Lua syntax, runs offscreen load tests for `shell.qml` and `greeter.qml`, fast-forwards `stable`, runs migrations, and restarts the shell (rolling back automatically if startup fails) |
| `kuwai update-self --ref REF` | Follows an explicit git ref (unsigned, for testing; `KUWAI_UPDATE_REF` is ignored) |
| `kuwai rollback` | Reverts `stable` to `stable-prev`, undoing migrations introduced after that commit |
| `kuwai channel [stable\|dev]` | Show or switch whether `kuwai-shell.service` runs `~/.local/share/kuwai` or your dev checkout |
| `kuwai promote` | Validates dev `HEAD` (`kuwai-check`, backup, `qmllint`, `pdeathsig` check, Lua parse, load tests, migration check) and fast-forwards `stable` |
| `kuwai migrations` | Lists, runs, or undoes (`--undo N`) state/config migrations |
| `kuwai backup` | Snapshots user config/state files; supports diff and restore |
| `kuwai export [FILE]` | Exports a portable machine manifest (packages, monitors, settings; no secrets) |
| `kuwai release vX.Y.Z` | Maintainer command: signs a tag on `main` with `~/.ssh/kuwai_release` verified against `release-signers` |

## Uninstalling

```sh
./install.sh --uninstall
```

This restores the files and systemd unit states captured before the first install. Your `~/.config/kuwai` settings and notes are kept. To remove the remaining pieces completely:

```sh
rm -rf ~/.local/share/kuwai
sudo system/session --undo
kuwai auth unpin
sudo greeter/install --undo   # if installed
sudo system/install --undo    # if installed
```
