# Looks: themes, wallpapers, live wallpapers, screensavers

Everything here is picked in one place: **Super+Shift+T** (Themes), then
**Tab** between *Themes · Wallpapers · Live · Screensaver*. ↵ applies, F
favourites a theme, P shows a screensaver now. These are your files under
your home folder; nothing needs root.

| Kind | Where it lives | Add one | Shows up |
|---|---|---|---|
| Theme | `~/.config/hyde/themes/<Name>/` | HyDE's installer (below) | Themes tab, with its palette |
| Wallpaper | `~/.config/hyde/themes/<Theme>/wallpapers/` | copy an image in | Wallpapers tab (current theme's) |
| Live wallpaper | `~/Pictures/live-wallpapers/` (or a theme's `wallpapers/live/`) | `rice-wall add FILE.mp4 "name"` | Live tab; Super+Ctrl+Shift+W steps through |
| Screensaver film | `~/.local/share/rice/screensavers/` | `rice saver add FILE.mp4 [name]` | Screensaver tab, as "Night · Name" |

## Themes

A theme is a folder with a palette for each app (`kitty.theme`,
`hypr.theme`, `waybar.theme`, …) and its wallpapers. Install one from a Git
repository or a local folder with HyDE's installer:

```sh
~/.local/lib/hyde/theme.patch.sh "Theme-Name" https://github.com/User/Repository
~/.local/lib/hyde/theme.patch.sh "Theme-Name" /path/to/configs
```

It appears in the Themes tab on the next open. The island's accent follows
the theme (Settings → Colours: from the theme, the wallpaper, or forced
dark/light).

**Worth it when:** the palette has one clear accent and near-black
surfaces. Themes with several loud accents fight the island's rule of
"colour only for state".

## Wallpapers

Drop images into the current theme's `wallpapers/` folder. PNG/JPG at your
largest screen's size (2560×1440 here) or larger. Wallbash recolours apps
from the wallpaper when Colours is set to *Wallpaper*.

**Worth it when:** the top 60 px is calm and dark: the island and its
text sit there.

## Live wallpapers

```sh
rice-wall add ~/Videos/rain.mp4 "rain"      # 30 fps, ≤1440p, GPU-encoded, seamless loop
rice-wall import ~/.local/share/Steam/steamapps/workshop/content/431960   # Wallpaper Engine's *video* wallpapers
rice-wall list                              # the library, in play order
```

`add` makes the loop seamless (the last 1.5 s fade into the first) unless the
clip already loops. Live wallpapers play behind your windows and pause when
windows cover them; on battery they stay off unless Settings allows them.

**Worth it when:** slow and dark (rain, fog, night skies, slow abstract).
Fast or bright clips cost battery and pull focus. Wallpaper Engine's *scene*
and *web* wallpapers can't be imported (only video ones); legally you need the
Workshop items you subscribed to with your own Wallpaper Engine.

## Screensavers

```sh
rice saver add ~/Videos/ink.mp4 "ink"   # half speed, played forward then back (no seam), slightly darker, + thumbnail
rice saver list
rice saver remove ink
rice screensaver                        # show it now (any key or move ends it)
```

Pick it in **Themes → Screensaver** (or Settings → Screensaver, which also
has *when*: with Caffeine, always, or off, and *after how long*). The other
choices: **Dusk** (drawn live, nothing to decode), **Live wallpaper** (the
current one, full screen), **Still wallpaper** (slowly drifting).

The film plays in its own small process on the screen you were using, black
on the others, and is gone the moment you're back, memory included.

**Worth it when:** mostly black with slow movement (smoke, stars, aurora).
Near-black is kind to OLED and never distracting.

Free, no-attribution sources: Mixkit (mixkit.co/free-stock-video), Pexels
Videos, Pixabay Videos. Check each clip's licence.
