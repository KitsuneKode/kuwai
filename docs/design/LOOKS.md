# Looks: themes, wallpapers, live wallpapers, screensavers

How kuwai's look is built and judged. The user's guide is `docs/manual/looks.md`; the tokens
are `shell/config/Theme.qml`; how kuwai stands without HyDE is `docs/design/WITHOUT-HYDE.md`;
the study behind this is `docs/research/2026-11-15-atmosphere-references.md`.

## One atmosphere, several moods

kuwai is one look: near-black liquid glass, a 1 px specular rim, colour kept for state. A theme
is a **mood inside that look**, not a costume. It changes colour and pictures. The shape stays
the same everywhere, so every theme still reads as kuwai.

| A theme says (`themes/<slug>/theme.toml`, `palette.toml`) | kuwai says, the same in every theme (`hypr/kuwai/look.lua` `L.SHAPE`) |
|---|---|
| name, mode, **one accent** | window corners **18**, squircle (`rounding_power 4`) |
| ground, ink, secondary and tertiary (`[colors]`) | frame **2 px** |
| optionally its own terminal palette (`[ansi]`, sixteen colours) | gaps 5 / 10 |
| its wallpapers (`wallpapers.tsv`) and their credits | no dimming, opaque windows |
| for a HyDE theme: `hypr.theme`, `kitty.theme`, `ghostty.theme` | one shadow (40, 0 12), one glow (12 px) |
| | blur (≤ 3 passes), motion, fonts, GTK, icons |

`kuwai-look theme NAME` reads the palette (`palette.toml`, else a `kitty.theme`, else HyDE's
`theme.dcol`), builds every role from it (`lib/look/roles.py`: a missing `[ansi]` is made from
the accent and checked for contrast) and writes the generation the shell, Hyprland, kitty, GTK
and Qt read (`lib/look/render.py`). A theme carries only what it means to change.

A HyDE theme from elsewhere still works: whatever shape its `theme.conf` asks for, `L.SHAPE`
lands after it, and only its colours stay (`tests/hypr/test_look_shape.lua`). Modes (Gaming,
Battery) and `user.lua` load after the look, so they still turn the glow, shadow or corners off.

### Corners: one family

Concentric, as Apple does it: an inner radius is the outer one minus the padding between them.

| Surface | Radius | Where |
|---|---:|---|
| Panels (island, centre, launcher) | 22 | `Theme.r4` |
| Windows | 18 | `L.SHAPE` |
| Cards | 16 | `Theme.r3` |
| Tiles, switches | 12 | `Theme.r2` |
| Small controls, thumbnails | 8 | `Theme.r1` |

The HyDE-era themes used 10 to 25 px window corners, so the island and the windows disagreed in
nine of eleven themes.

### Borders and glow: one hue

The focused window wears the theme's accent, brightest at the top-left (`b3`) fading to `4d` at
45°, and an inner glow in the same hue (`40` → `14`). The others wear the palette's border
colour at `55`. One hue, never two competing ones (`accentSoft` turned the rim muddy). Without a
kuwai palette the rim is white. The glow is off where it gets in the way: a lone tile,
fullscreen, video, photos, picture-in-picture, games (`hypr/kuwai/rules.lua`,
`tests/hypr/test_look_glow.lua`).

### Palette rules (`lib/look/roles.py`)

- The ground is clamped calm and low-chroma (`clamp_ground`); a kuwai theme is a dark one.
- The accent is made vivid enough to read on the glass (`vivid_accent`, the twin of
  `Theme.vivid`), so the swatch, the terminal's blue and the island's glow are one colour.
- Generated terminal colours keep their meaning (red is an error, green is done) and are pushed
  to 4.5:1 or better on the ground (`ensure_contrast`). A theme's own `[ansi]` is kept as given.

## The wallpaper gate (`bin/kuwai-wallcheck`)

It measures each picture as a 2560×1440 screen shows it, cropped to fill:

| Rule | Fails | Warns |
|---|---|---|
| size | upscaled more than ×1.35 | any upscale |
| crop | | the 16:9 crop loses more than 30 % |
| strip (top 60 px, under the island) | mean L* above 53 | mean L* above 38, or spread above 14 |
| bars | letterboxing: flat black ending in a straight edge (a silhouette is not a bar) | |
| band | mean L* more than 12 above the band (default 6–48) | outside the band |
| loud | | more than 20 % bright and saturated |
| text (`--ocr`) | | words found: logos, captions, watermarks |
| twin | near-duplicate in the same run (dHash ≤ 6 bits) | |
| clock | the lock clock under 3:1 even with its shade | the clock needs the shade |
| `--tsv` | a row not pinned, licence not shippable, no author | |

`--sheet OUT.jpg` draws a contact sheet with each verdict and the island's strip outlined. Curate
by eye on that sheet: the gate removes the clearly bad, and a person chooses.

## Where good, licensed pictures and films are

| Source | Licence | Good for |
|---|---|---|
| Wikimedia Commons, Featured and Quality images (`filew:>2559`) | per file, in the API (`extmetadata.LicenseShortName`) | landscapes, night sky, aurora |
| NASA (ISS crew photography, SVS visualisations) | public domain (no NASA logo) | Earth at night, aurora from orbit |
| ESA/Webb, ESA/Hubble, ESO | CC BY 4.0, credit as given | deep sky, Paranal skies |
| Pepper&Carrot (David Revoy) | CC BY 4.0 | a licensed illustrated theme, still to curate |
| Blender Studio open films | CC BY | painterly stills, still to check per film |
| Pexels, Pixabay, Mixkit, Coverr | free to use, **not** to redistribute as wallpapers | personal use only; never in a kuwai theme |
| Unsplash | its API asks for hotlinking and download tracking | not for a theme pack |
| YouTube, wallhaven toplists, MoeWalls | none | personal packs only, never shipped or suggested |

Wikimedia throttles anonymous clients: fetch one file at a time, under a named user-agent.

## Open work

1. **A drawn screensaver** in the glass language, to replace Dusk's clip-art.
2. **Signature images**: a "night glass" still set rendered from kuwai's own shaders, owned and
   licensed by the project, and one slow seamless loop in the accent.
3. **A licensed illustrated theme** (Pepper&Carrot, Blender films).
4. **One-event theme change**: the WallFx reveal, the accent blend and the border land together.
