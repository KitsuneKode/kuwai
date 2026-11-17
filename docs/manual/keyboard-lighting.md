# Keyboard lighting that matches a theme

Written for an Aula F75 (here it shows up as `258a:010c "BY Tech Gaming Keyboard"` in `lsusb`), but the colour
advice holds for any RGB board.

## What I could and couldn't establish

- I found **no confirmed Linux control** for this board: nothing lists it in OpenRGB, and sources disagree on
  whether the F75 takes QMK or VIA (some say yes, a review of the F75 *Pro* says no). Check yours with
  `lsusb` (the ID above) before buying or flashing anything.
- Buyers of the wired F75 report **preset lighting modes without per-key colour**. So the practical way to
  match a theme is the board's own modes and colour presets (its Fn combinations are in its manual), or the
  maker's configurator (Epomaker's is browser-based; try it from Chromium).
- kuwai doesn't drive the keyboard. The only light it touches is the laptop's own (`hypridle` dims
  `rgb:kbd_backlight` while idle).

## Colour that actually shows

An RGB LED makes colour by mixing a red, a green and a blue diode. That changes what looks good:

1. **Pastels turn white.** The island's accents are soft (sakura pink `#f5a9c8`); on keys, mixed-in green and
   blue make that read as white. Use the fully saturated version of the hue.
2. **Blue is the dimmest diode, green the brightest.** A pure blue looks dark next to green. Nudge blue and
   violet toward cyan or magenta (more red or green in the mix) to keep them lively.
3. **One colour, two at most.** The accent plus a second hue from the same theme looks designed; a rainbow
   fights every wallpaper.
4. **Turn the brightness down at night.** Keys glare against a dark desktop; ~40 % reads as a glow, 100 % as a
   light.

## Colours for each theme

These are my picks from how LEDs mix, not measured on your board: if a preset can't make the exact colour,
take the nearest one.

| Theme | Island accent | Keys | Nearest preset |
|---|---|---|---|
| Kuwai Night | neutral | `#3d7bff` at low brightness, or cool white | blue / white |
| Sakura Night | `#f5a9c8` | `#ff2f92` | pink |
| Neon District | `#3ee6ff` | `#00e5ff` (+ `#ff2fd0` for a second colour) | cyan |
| Garage | `#ff5a3c` | `#ff3b00` | red / orange |
| Void | `#8ab4ff` | `#1a8cff` | blue |
| Aurora | `#5eead4` | `#00ffc8` | aqua / green |
| Pixel Dusk | `#ffb86b` | `#ff9500` | orange |
| Crimson Noir | `#ff4d6a` | `#ff0a3c` | red |
| Violet Hour | `#b48cff` | `#a040ff` | purple |
| Chrome Sunset | `#ff3fb0` | `#ff1fa8` (+ `#00d9ff`) | pink / magenta |
| Matcha | `#8fe3a2` | `#39ff7a` | green |
