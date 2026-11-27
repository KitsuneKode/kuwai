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

kuwai offers 3 verified, digest-pinned dark themes by default under `themes/`. **No third-party wallpaper images are shipped in the repository.** Each default theme lists SHA-pinned Wikimedia Commons URLs, licences, authors and source pages in `themes/<slug>/wallpapers.tsv` (checked by `kuwai-wallcheck --default`) with full attributions in `themes/<slug>/CREDITS.txt`. Applying a theme downloads its first wallpaper on first use (verifying its digest before writing it), and `kuwai-theme install <slug> [--apply]` downloads the full set.

| Slug | Accent | Mood | Licence |
| --- | --- | --- | --- |
| `kuwai-night` | `#66c7ff` | Night skies and mountains (default look) | Public domain (NPS), CC BY 4.0 (ESO), CC0 |
| `deep-field` | `#a48bff` | Deep-sky photography (Webb, Hubble, Euclid) | Public domain (NASA), CC BY 4.0 / CC BY-SA 3.0 / CC0 |
| `earthlight` | `#ffad4a` | Earth and orbital photography (ISS crew) | Public domain (NASA) |

Ten additional personal-use palettes (`aurora`, `chrome-sunset`, `crimson-noir`, `garage`, `matcha`, `neon-district`, `pixel-dusk`, `sakura-night`, `violet-hour`, `void`) carry `personal = true` in `theme.toml` because their `wallpapers.tsv` links point to Wallhaven images without a verifiable redistributable licence. They are not offered by default in `kuwai-look list` or the Themes panel; pass `--all` to `kuwai-look list` or apply a palette explicitly by slug if you use your own wallpapers.

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

Several styles are available in **`Themes → Screensaver`** or **`Settings → Screensaver`**:

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

### Going dark after a long wait

After an hour on the screensaver (`Settings → Screensaver → Then go dark`: 30 min, 1 h, 2 h or never; `screensaverLongMins`) it fades over a few seconds to a dim clock and date on black, with nothing drawn or decoded behind them: kind to an OLED panel and to the battery. It only has work to do when nothing else ends the screensaver first. If the screen locks, or your own idle settings turn the screens off, within that hour, those do it and the setting says so. Any key or movement wakes it as before.

### Photos

The **Photos** look shows one picture at a time, fading slowly into the next every few minutes (`Settings → Screensaver → Change photo`: 1, 5, 15 or 30 min). By default the pictures are your current theme's wallpapers; to use a folder instead, `kuwai set screensaverFolder "~/Pictures/favourites"` (one level of the folder, `jpg`, `png` and `webp`; `kuwai set screensaverFolder ""` goes back). Each screen follows its own shuffle. Only the picture on screen and the next one are held in memory, decoded at screen size; between changes nothing moves. A folder with no pictures shows the still wallpaper.
