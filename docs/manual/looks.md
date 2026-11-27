# Looks: themes, wallpapers, live wallpapers, and screensavers

Open the picker with **`Super+Shift+T`** (Themes) or **`Super+Shift+W`** (Wallpapers), then press **`Tab`** to switch between *Themes · Wallpapers · Live · Screensaver*. Press **`Enter`** to apply, **`F`** to favourite a theme, or **`P`** to preview a screensaver immediately. Everything here lives in your home directory and requires no root privileges.

## Standalone look engine (`kuwai look`)

kuwai includes its own palette and wallpaper engine (`bin/kuwai-look`), so HyDE is optional:

```sh
kuwai look list                          # list available themes
kuwai look theme kuwai-night             # apply a theme atomically
kuwai look set-wallpaper ~/Pictures/w.jpg # set wallpaper and extract palette
kuwai look mode theme|auto|dark|light    # switch colour derivation mode
kuwai look install <git-url> [slug]      # validate and install a user theme repo
kuwai look undo                          # revert to the previous look generation
```

Palette switches run WCAG 4.5:1 contrast checks and update the shell, Hyprland borders, and terminal colours together. Custom templates can be placed in `~/.config/kuwai/custom/templates/` and post-switch hooks in `~/.config/kuwai/custom/hooks/look-changed.d/`.

If HyDE is installed, kuwai continues to read HyDE themes and wallpapers alongside its own.

## Shipped themes

kuwai ships 13 dark theme definitions under `themes/`. **No third-party wallpaper images are shipped in the repository.** Each theme lists pinned wallpaper URLs and checksums in `themes/<slug>/wallpapers.tsv` and full attributions in `themes/<slug>/CREDITS.txt`. Run `kuwai-theme install <slug> [--apply]` to download a theme's wallpapers to your machine for personal use with `CREDITS.txt` copied beside them.

| Slug | Accent | Mood |
| --- | --- | --- |
| `kuwai-night` | `#66c7ff` | Dark photographs, default look |
| `aurora` | `#5eead4` | Mountains, night skies, nebulae |
| `chrome-sunset` | `#ff3fb0` | Synthwave, city pop, retro cars |
| `crimson-noir` | `#ff4d6a` | Dark illustrated and gothic art |
| `deep-field` | `#a48bff` | Deep-sky photography (Wikimedia Commons) |
| `earthlight` | `#ffad4a` | Earth and orbital photography (Wikimedia Commons) |
| `garage` | `#ff5a3c` | Automotive photography and art |
| `matcha` | `#8fe3a2` | Soft green forest and cosy scenes |
| `neon-district` | `#3ee6ff` | Cyberpunk and night cities |
| `pixel-dusk` | `#ffb86b` | Pixel art and warm dusk scenes |
| `sakura-night` | `#f5a9c8` | Soft pink night illustrations |
| `violet-hour` | `#b48cff` | Moonlit violet art |
| `void` | `#8ab4ff` | Minimal dark and abstract |

Every theme keeps kuwai's shared window geometry and motion curves (`hypr/kuwai/look.lua`, `hypr/kuwai/motion.lua`); only colour and imagery change.

## Wallpapers

- Step through still wallpapers with **`Super+Alt+]`** (next) and **`Super+Alt+[`** (previous).
- Set any image directly without HyDE: `kuwai-wall set ~/Pictures/image.jpg` (restored at login by `kuwai-wallpaper.service`).
- Check whether a picture works well under the island and lock clock: `kuwai-wallcheck IMAGE`. Images with a dark, calm top 60 px strip keep the island legible.
- Wallpaper changes spread out from the notch using a shader transition (`WallFx`). Optional subject-first transitions can be enabled by installing the segmentation model with `kuwai-wallmap --install` (once, ~1 GB).

## Live wallpapers

```sh
kuwai-wall add ~/Videos/rain.mp4 rain   # re-encode to ≤1440p 30 fps seamless loop
kuwai-wall import <steam-workshop-dir>  # import your own Wallpaper Engine video items
kuwai-wall list                         # list live wallpapers in play order
kuwai-wall play NAME|FILE               # play one now
```

Live wallpapers are stored in `~/Pictures/live-wallpapers/` (or a theme's `wallpapers/live/`). Step through them with **`Super+Ctrl+]`** and **`Super+Ctrl+[`**. They pause automatically when windows cover them and stay off on battery unless enabled in Settings.

## Screensavers

Five styles are available in **`Themes → Screensaver`** or **`Settings → Screensaver`**:

- **Dusk** and **Borealis** — live shaders (Borealis follows your theme accent; no video decoding).
- **Night** — seamless half-speed looping films stored in `~/.local/share/kuwai-data/screensavers/`, played in a separate `shell-saver` process whose memory is reclaimed immediately on wake.
- **Live wallpaper** — plays the current live wallpaper full screen.
- **Still wallpaper** — displays the current still wallpaper with subtle drift.

Manage Night films and trigger the screensaver from the CLI:

```sh
kuwai saver add ~/Videos/loop.mp4 loop  # creates a seamless half-speed loop + thumbnail
kuwai saver list
kuwai saver remove loop
kuwai screensaver start                 # show now (or Super+Alt+Shift+S)
```

Step between screensavers with **`Super+Ctrl+Alt+]`** and **`Super+Ctrl+Alt+[`**. By default, the screensaver is a step of the idle ladder: your still wallpaper with the time comes up before the screen fades and locks, and the lock keeps its usual time. While Caffeine holds the lock off, it comes after its own minutes (`Settings → Screensaver → When`: `always`, `caffeine` for only while Caffeine is on, or `off`).
