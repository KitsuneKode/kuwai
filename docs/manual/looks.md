# Looks: themes, wallpapers, live wallpapers, screensavers

Everything here is picked in one place: **Super+Shift+T** (Themes), then
**Tab** between *Themes · Wallpapers · Live · Screensaver*. ↵ applies, F
favourites a theme, P shows a screensaver now. These are your files under
your home folder; nothing needs root.

| Kind | Where it lives | Add one | Shows up |
|---|---|---|---|
| Theme | `~/.config/hyde/themes/<Name>/` | HyDE's installer (below) | Themes tab, with its palette |
| Wallpaper | `~/.config/hyde/themes/<Theme>/wallpapers/` | copy an image in | Wallpapers tab (current theme's) |
| Live wallpaper | `~/Pictures/live-wallpapers/` (or a theme's `wallpapers/live/`) | `kuwai-wall add FILE.mp4 "name"` | Live tab; Super+Ctrl+Shift+W steps through |
| Screensaver film | `~/.local/share/kuwai/screensavers/` | `kuwai saver add FILE.mp4 [name]` | Screensaver tab, as "Night · Name" |

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

### The themes kuwai ships

`kuwai-theme install NAME` (add `--apply` to switch to it) puts one in place:
its terminal palette (kitty and Ghostty), hairline borders in its accent,
and its wallpapers, downloaded to your machine (nothing here ships the
images; `themes/NAME/CREDITS.txt` says where each came from). GTK theme,
icons and font stay yours.

| Name | Accent | For |
|---|---|---|
| `kuwai-night` | none (hairlines) | photographs, the default |
| `sakura-night` | sakura pink `#f5a9c8` | anime art |
| `neon-district` | neon cyan `#3ee6ff` | cyberpunk, night cities |
| `garage` | tail-light orange `#ff5a3c` | cars |
| `void` | ice blue `#8ab4ff` | dark minimal, abstract |
| `aurora` | northern teal `#5eead4` | mountains, night skies, nebulae |
| `pixel-dusk` | amber `#ffb86b` | pixel art, lofi |
| `crimson-noir` | crimson `#ff4d6a` | dark and gothic anime and manhwa art |
| `violet-hour` | violet `#b48cff` | moonlit, violet anime art |
| `chrome-sunset` | hot pink `#ff3fb0` | synthwave, city pop, retro cars |
| `matcha` | soft green `#8fe3a2` | cosy, forest and Ghibli-style scenes |

Wallpapers are illustrations and CG art, safe for work. Matching keyboard colours:
[keyboard-lighting.md](keyboard-lighting.md).

What a theme can set in Hyprland, besides colour: the active border (an accent gradient), corner
rounding, window shadow, the group bar and **glow** (a soft accent halo round the focused window, on in Neon
District, Crimson Noir and Chrome Sunset, off elsewhere: it costs a GPU pass, so it stays a deliberate choice).
Blur strength and passes are kuwai's (`hypr/kuwai/look.lua` caps them for the battery) and motion is kuwai's
too. A full-screen shader (`decoration:screen_shader`) could add grain or a vignette but runs on every frame
of every screen, so no theme turns it on.

The accent is the palette's blue slot (`color4`), so it is also the island's
colour. Every palette reads at 4.5:1 or better on its background
(`tests/test_shipped_themes.py` checks it). Motion is not a theme's to set: the
springs and curves are kuwai's own (`hypr/kuwai/motion.lua`), the same in every
theme, and a wallpaper change is drawn by the shell (`WallFx`).

**Make the wallpaper change draw its subject first.** `kuwai-wallmap --install`
(once, about 1 GB) adds the cut-out model; `kuwai-wallmap --warm DIR` makes the
maps ahead of time. A picture with a character or a car gets its outline
traced and filled before the rest spreads out from it; one without a subject,
or any picture before its map exists, gets the cut pieces instead.

## Wallpapers

Drop images into the current theme's `wallpapers/` folder. PNG/JPG at your
largest screen's size (2560×1440 here) or larger. Wallbash recolours apps
from the wallpaper when Colours is set to *Wallpaper*.

**Worth it when:** the top 60 px is calm and dark: the island and its
text sit there.

## Live wallpapers

```sh
kuwai-wall add ~/Videos/rain.mp4 "rain"      # 30 fps, ≤1440p, GPU-encoded, seamless loop
kuwai-wall import ~/.local/share/Steam/steamapps/workshop/content/431960   # Wallpaper Engine's *video* wallpapers
kuwai-wall list                              # the library, in play order
```

`add` makes the loop seamless (the last 1.5 s fade into the first) unless the
clip already loops. Live wallpapers play behind your windows and pause when
windows cover them; on battery they stay off unless Settings allows them.

**Which live wallpaper goes with which theme** (numbers are the Live tab's order; found and sorted in
`docs/research/2026-11-18-live-wallpaper-sources.md`):

| Theme | Good matches |
|---|---|
| Crimson Noir | 18 madara-uchiha · 19 kaneki-ken · 21 red-eyed-white-haired-girl |
| Neon District | 23 cyberpunk-night-city · 24 cyberpunk-night-city-walk · 22 samurai-girl-and-dragon |
| Violet Hour | 25 shibuya-after-dark · 26 galaxy-eye-anime-girl · 22 samurai-girl-and-dragon |
| Void | 20 black-angel · 27 girl-behind-curtains |
| Sakura Night | 17 neko-chan-daisuki-toko-toko · 28–33 the keshi clips (pastel and bright: best with the island's top strip over a calm area) |
| Chrome Sunset, Garage | 23 / 24 (night city rain) |
| Matcha | 29 keshi-library-and-cat |

The dark ones (18–27) sit best under the island: near-black along the top. The keshi clips are bright and
carry the creator's `X @keshiAIart` mark.

**Where to get them.** Wallpaper Engine's Workshop, with your own copy of
the app (above); Pexels, Pixabay and Mixkit, whose licences allow free use; a
YouTube video only when its licence says Creative Commons (search filter
*Features → Creative Commons*) or its owner says it is free to use, since
downloading the rest breaks YouTube's terms. Sites that re-post Workshop
wallpapers as plain mp4 (MoeWalls is the best known) credit the artist, but the
artist has not necessarily agreed: whether to use them is your call. Only the
site's own domain: copies of these sites on look-alike domains (`*.pages.dev`
and the like) are not them. `kuwai-wall add` runs every file through ffmpeg,
so what lands in the library is a plain re-encoded video, never the original
file.

**Worth it when:** slow and dark (rain, fog, night skies, slow abstract).
Fast or bright clips cost battery and pull focus. Wallpaper Engine's *scene*
and *web* wallpapers can't be imported (only video ones); legally you need the
Workshop items you subscribed to with your own Wallpaper Engine.

## Screensavers

```sh
kuwai saver add ~/Videos/ink.mp4 "ink"   # half speed, played forward then back (no seam), slightly darker, + thumbnail
kuwai saver list
kuwai saver remove ink
kuwai screensaver                        # show it now (any key or move ends it)
```

Pick it in **Themes → Screensaver** (or Settings → Screensaver, which also
has *when*: with Caffeine, always, or off, and *after how long*). The other
choices: **Dusk** (an evening, drawn live, nothing to decode), **Borealis**
(northern lights in your theme's own accent, also drawn live: switch theme and
the sky changes colour), **Live wallpaper** (the current one, full screen),
**Still wallpaper** (slowly drifting).

Nothing comes on by itself unless *when* allows it: the default is "with
Caffeine on" (otherwise the machine dims and locks as usual). To see a choice
right away press **P** on it in the Themes tab, or run `kuwai screensaver`.
A film that can't start (its file is missing) falls back to Dusk for that
showing only; the shell's log says which file (`qs log | grep screensaver`).

The film plays in its own small process on the screen you were using, black
on the others, and is gone the moment you're back, memory included.

**Worth it when:** mostly black with slow movement (smoke, stars, aurora).
Near-black is kind to OLED and never distracting.

Free, no-attribution sources: Mixkit (mixkit.co/free-stock-video), Pexels
Videos, Pixabay Videos. Check each clip's licence.
