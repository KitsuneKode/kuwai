# Changelog

## 0.2.0

### Standalone Desktop & Architecture
- Removed HyDE requirement from Kuwai-native binds, systemd units, environment detection, greeter, and settings preview.
- Split package manifests into `packages/core.txt`, `packages/optional.txt`, and `packages/fonts.txt` with non-interactive `install.sh --yes` support.
- Added layer-boundary (`bin/kuwai-layers`) and HyDE-isolation (`bin/kuwai-hyde-ratchet`) architecture gates to `bin/kuwai-check`.
- Overhauled `bin/kuwai-update` and `bin/kuwai-update-root` with `!debug` AUR builds, 1 GiB LRU artifact cap, automatic `makepkg -c` cleanup, `kuwai-update storage`, and `kuwai-update clean`.

### Look & Theme Engine
- Added `systemd/kuwai-wallpaper.service` (`awww-daemon`) and atomic single-writer `bin/kuwai-look` (`set-wallpaper`, `theme`, `mode`, `install`, `undo`, `init`, `status`, `list`).
- Added WCAG contrast-enforced palette generation, atomic `look/current` symlink swap, custom user templates (`~/.config/kuwai/custom/templates/*.tpl`), and user hooks (`~/.config/kuwai/custom/hooks/look-changed.d/`).
- Added native `theme.toml` + `palette.toml` to all 11 bundled themes, strict allowlist-validated `kuwai-look install <repo>`, and portable app include configs (`kitty`, `gtk-3.0`, `gtk-4.0`, `qt6ct`).

### UI Craft Primitives & Distribution
- Added unified `BlurShape`, `Material`, `Pressable`, `FocusGrabber`, `ContentSwap`, `EmptyState`, `StateView`, `PanelFrame`, `Look`, and `Sound` primitives/services.
- Upgraded `GreeterView` with adaptive `ClockGround` scrim + `FocusGrabber`, `T3Code`/`T3Panel` with last-good offline persistence, and `ThemePanel` with standalone `kuwai-look` support.
- Added `bin/kuwai-webapp`, `bin/kuwai-profile` (`export`/`diff`), and `kuwai rollback` / `kuwai update-self`.
