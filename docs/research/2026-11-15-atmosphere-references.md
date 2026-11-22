# Atmosphere: what to keep, what to take

Read-only study, 2026-11-15. Nothing in the shell was changed. pocket-dots is GPL-3.0, so this file keeps ideas and measured facts, not code to paste. t3code-bar is MIT. Wallhaven images stay as links until a licence is checked for each file.

Sources:

- This repo: `shell/config/Theme.qml`, `shell/shaders/liquidrim.frag`, `docs/DESIGN.md`, `docs/BORROWING.md`.
- [pocket-dots](https://github.com/diegoMalagrida/pocket-dots) at `main` (HEAD cited by the study as f1480297, 2026-11-14). Contrast, the liquid shader, and the wallpaper shader were re-read from raw source on 2026-11-15.
- [t3code-bar](https://github.com/eliophan/t3code-bar), from the craft study of `desktop/src/style.css`, `linux_appearance.rs`, and `attention.rs`.
- [wallhaven.cc](https://wallhaven.cc) SFW search, `purity=100`, `atleast=2560x1440`, on 2026-11-15.

## Decision

Kuwai's atmosphere should stay liquid glass. The glass, the rim, the damped motion, and the frame budget are already the identity, and both references are opaque black rectangles that would erase it. The gap is the picture and the proof that type on that picture can be read. A later change earns attention by giving the wallpaper a taste, solving ink against the real crop, and making a wallpaper change a short event that exists only while it plays.

## What kuwai already is

Re-read from `Theme.qml`: one near-black `#111114` (`Qt.rgba(0.067, 0.067, 0.078, …)`) at 0.58, 0.68 on text-heavy cards, 0.74 on menus, and 0.84 on the island. High contrast pushes those to 0.94–0.98. The file's own comment says motion is critically damped, no bounce. The rim shader is a static edge light, not a sample of the backdrop, and it is not a full-screen pass.

The atmosphere audit scored this layer taste 6, craft 7, performance 8. Stills still come through HyDE's `wallpaper.sh`. Live video pauses on battery, lock, the screensaver, fullscreen, and high window coverage. There is no shader wallpaper and no grade that follows the picture. The greeter falls back to `post-apocalyptic_hacker.png` with accent `#fc2e64`. `Theme.qml`'s header still says the UI face is Inter, while `docs/DESIGN.md` says SF Pro. That comment is drift. It is not a reason to change type.

`shell/services/Notifs.qml` has a `readable()` that cleans notification text. It is not a contrast function. `shell/modules/voxtype/VoxTarget.qml` already asks Hyprland for `decoration:rounding`. The shell's own radii stay the `r1`–`r4` tokens.

## What the references actually are

**pocket-dots** is a Hyprland + Quickshell rice whose shell is one opaque black notch. The shell README says blur is withheld on purpose, because an opaque surface would turn it into a smudge (`README.en.md` around the blur note). Windows are square. Unfocused windows are at 0.90 opacity, and only the focused window casts a shadow. Color is pywal at `--saturate 0.5`. The bundled wallpaper pack has no single atmosphere, and the author's own notes say most of the images have no clear licence. The Pokémon layer is costume. Taste 6, craft 8. It does not beat kuwai on taste. It is ahead only on the wallpaper pipeline and on how ink is chosen. It has no reduced-motion setting for the Quickshell animations, and battery mode does not gate the blur behind unfocused windows or the liquid shader. A second read of the same commit, after that study resumed, agrees on the scores. Contagion cells are 1/480 of the screen width, so they are 4 px only at 1080p. Outline cells are a fixed 4 px. Power-saver turns motion blur off, and nothing else in that blur stack. The outline cut-out can hold a change for up to 25 seconds.

**t3code-bar** is not a bar and not a rice. It is an MIT Tauri popover, 320 px wide, at most 560 px tall, radius 13, solid `#000`, a 1 px `#191919` inset, system font at 12 px, tabular numerals, one 180 ms fade. No shader, no wallpaper sample. On Linux it reads GTK colors, Omarchy's `colors.toml`, and Hyprland rounding, then checks the serialized 8-bit color: 7:1 for the first foreground/background pair, 4.5:1 for text, 3:1 for borders. That math is for an opaque surface. It does not solve text on kuwai's glass. A second read (tree `8220598`, after the Codex limit) found the reduced-motion rule misses the preview's own keyframe, and a one-second loop refreshes threads and usage while the panel is visible. Taste 7, craft 8, performance 7, for a utility popover, not for a desktop.

**Wallhaven**, scored for this glass and not for popularity. The toplist rewards neon, a face in the middle, and high-key scenes. Those fail here. What survives: dark indigo with no object, fog, blue-hour architecture with the warm light as a point, and near-black liquid or monochrome texture. Top four, all general and SFW: [o5j7v7](https://wallhaven.cc/w/o5j7v7) 9.6, [x8pdvl](https://wallhaven.cc/w/x8pdvl) 9.4, [7jx5l3](https://wallhaven.cc/w/7jx5l3) 9.2, [rrpp6m](https://wallhaven.cc/w/rrpp6m) 9.0. Reject on tags, not on the color chips. The API returned 429 after 45 detail calls.

## The logic

1. **Material is chosen per surface.** pocket-dots is right that blur on an opaque slab is a smudge. kuwai is right to blur, because the tint is actually translucent. Do not import their black slab to "match" them. Do not put pocket-dots' always-on blur behind 0.90 windows into kuwai. Focus mode, with opaque windows, is the cheaper and clearer choice.
2. **The picture is a material, not a theme download.** The glass is darker than a 46% myth (`0.58` to `0.84`), so a loud wallpaper still shows through the panels and dies behind the island. Taste moves only when the wallpaper is chosen for that fact. Neon, centred heroes, and the greeter's hacker plate fight the rim. Fog and near-black liquid give the blur something to refract and leave the Apple colors as the only saturated marks.
3. **Ink is solved, not assigned.** Re-read from pocket-dots `Colors.qml`: active ink on the wallpaper strip is pushed to 3.5:1, and it is opaque on purpose, because translucent ink landed on a color nobody picked. Four text levels are bisected to contrast targets 7 / 5 / 3.5 against the real background. Accent ink is pushed to 4.5:1. t3code-bar does the same kind of correction for theme colors, and it checks the 8-bit value the screen will actually show. kuwai's fixed tint never does this. It matters for the lock clock, the greeter, and anything else drawn on the picture. It does not mean the glass tint should become the wallpaper's average color. pywal at `--saturate 0.5` would break the near-black neutrality.
4. **A wallpaper change is an event with a budget.** Re-read from `wallfx.frag`: the shader does not know when a pixel flips. Offline maps do. Contagion cells are 1/480 of the width (4 px at 1080p). Outline cells are a fixed 4 px. Every extra effect is `sin(πt)`, so it is zero at both ends and the cut cannot show. The layer should exist only while the change plays, and a watchdog should fall back to a plain fade. The character-outline mode needs a subject. Fog and abstract walls have none, so that mode would always miss. Take the envelope, the bounded lifetime, and the fallback. Leave the 4 px cells and the outline mode.
5. **Edges are one pixel, and texture does not move.** Re-read from `liquid.frag`: coverage is `clamp(0.5 - d/fwidth(d))`, one pixel. A two-pixel `smoothstep` at an 8 px body reads as a smudge. Color mixed by distance painted a white ring. Color mixed by coverage did not. A tied field is removed by dissolving the dot, not by a later color hack. Their reading-mode grain is static and anchored to the pixel, because moving grain forces redraws. kuwai's rim is already in this family. Do not animate grain, and do not add a full-screen shader to get "more glass."
6. **Correctness is allowed to be quiet.** t3code-bar's focus grab, transition-only alerts, and late-service grace period are the craft. It also keeps last-good data and says when that data is offline, failed, stale, or revoked. A one-second loop still refreshes while the panel is open, and the panel is a WebKit surface. Quickshell can listen. It should not poll on a timer to imitate them.

## Later, in this order

1. Choose wallpapers by the Wallhaven rule above. Retire the hacker plate and the neon live clips as defaults.
2. Solve ink for text that sits on the wallpaper, against the real crop, after quantization. Keep the glass tint neutral.
3. Play a wallpaper change on a layer that exists only during the change, with a `sin(πt)` envelope and a fade fallback. Record frame time. No character outline.
4. Let shell corners follow `decoration:rounding`, the way the voice target already reads it.
5. Notify on a status change. If a dependency appears late, wait, then show a diagnostic.

## Do not take

- An opaque `#000` shell, a system font stack, or near-zero motion on the island, the drawer, and the toasts.
- pywal `--saturate 0.5` as the way the neutral palette is made.
- The Pokémon layer, the pixel clock, the mascot, and any wallpaper without a licence.
- Underdamped springs and an overshooting morph. kuwai's rule is critical damping.
- Blur behind every unfocused window.
- A full-screen shader as the wallpaper, a WebKit panel, or a 2-second theme poll.
- GPL source from pocket-dots, including shader text. Rewrite any idea in kuwai's tokens.

## Scores

| | Taste | Craft | Performance |
|---|---:|---:|---:|
| kuwai atmosphere | 6 | 7 | 8 |
| pocket-dots | 6 | 8 | not scored |
| t3code-bar | 7 | 8 | 7 |

pocket-dots was not given a performance score. The expensive fact is blur behind 0.90 windows, with a comment in their Hyprland config that this is the costly case, and a battery mode that does not turn that blur off.

## Clone, 2026-11-15

Shallow clone at `refs/diegoMalagrida_pocket-dots` (gitignored). Read from that tree: `WallpaperFx.qml`, `shaders/wallfx.frag`, `shaders/liquid.frag`, `set-wallpaper.sh`, `hyprland.lua` layer rules. Caffeine compared with `shell/services/Caffeine.qml`, `shell/services/Idle.qml`, and caelestia's `refs/caelestia-dots_shell/daemons/IdleInhibit.qml`.

### Where pocket-dots is actually good

The wallpaper change is a scene, not a fade lottery. `WallpaperFx.qml` draws on `WlrLayer.Bottom`, namespace `quickshell:wallfx`, for the length of the change only. The order is the whole trick: fade in over awww while the shader is still the old image (130 ms, so the fade is invisible), switch awww with `--transition-type none` underneath, end on the new image, fade out, drop the textures. Hyprland is told `no_anim` on that namespace, because a compositor fade would reveal the swap. There is no blur rule on it. Maps are built offline. `t` is linear. Extra light is `sin(πt)`, so both ends match awww and the cut cannot show. A 2.5 s watchdog exists. `qs ipc call wallfx stats` reports frames and the worst frame. The bar's ink is measured from the cropped top 5% of the focused screen, not from pywal's darkened background. They write that file atomically and delete it if ImageMagick fails, so a stale strip is never kept.

Their layer law is the other real lesson. One namespace per surface (`quickshell:bar`, `:wallfx`, `:wallpaper`, `:media`, `:stage`). The compositor animates only what the app does not. The bar resizes itself, so the bar rule is `no_anim`. Media rises from the bottom because the card already does scale and opacity. The picker covers the screen, so it does not slide.

### Where it is not good

The shell is an opaque black notch. Blur is refused there on purpose, and then spent on every unfocused window at 0.90 opacity. There is no caffeine switch, no shell-owned idle, and no reduced-motion path for the Quickshell animations. The wallpaper set has no taste, and most bundled images have no licence. pywal runs at `--saturate 0.5`. The outline transition needs a character, and its cut-out can hold the change for up to 25 seconds. Fog and abstract walls miss it and fall through to contagion. Those cells are a fraction of the screen, about 4 px at 1080p and about 5.3 px at 1440p, which fights smooth glass. `hyprctl reload` runs in `set-wallpaper.sh` after the transition has started, so the compositor reloads during the effect.

### Bugs in their wallpaper path

- If awww never answers, the transition ends in phase `held` and the watchdog calls `finish()` without setting the new image. The shader has been showing the new picture. Uncovering then reveals the old awww image. The comment above that timer says the layer steps aside because the new image is already underneath. The code only asks awww to fade when the phase was still `loading`.
- `OLD_IMG` is the first line of `awww query` (`head -n1`). Every screen's transition starts from that one image.
- The bar strip is the focused monitor only (`hyprctl monitors -j`, `select(.focused)`). A second screen with a different crop gets the wrong ink.
- Re-applying the same path can leave the `Image`s at `Ready` without another `onLoadedChanged`, so `screenReady` never reaches `screenCount` and the effect falls back to a plain fade.

### Bugs and layer mistakes here

- `hypr/kuwai/rules.lua` used to give every `rice-*` surface blur, including the live video. Fixed: the video layer is `kuwai-wallpaper`, with `no_anim` and no blur, same split as the screensaver. A later `blur = false` does not undo `rice-glass`, so the namespace had to leave `rice-*`.
- `LiveWallpaper.qml` used to add each window's rectangle into `coverage`. Overlapping windows were counted twice. Fixed: the area is the union of the clipped rectangles.
- A future transition layer must not be named `rice-*` or `quickshell*`. `rice-*` forces blur. `^quickshell.*$` forces blur with `ignore_alpha 0`. pocket-dots' wallfx stays sharp only because nothing blurs that namespace. Copy the lifetime and the hand-off. Give it its own namespace, `no_anim`, and no blur. The watchdog must force awww onto the new image before the layer is destroyed. Do not copy the held-phase snap-back.
- Caffeine is ahead of both references. caelestia's `IdleInhibit.qml` is only a Wayland `IdleInhibitor` on a 0×0 transparent window. `Caffeine.qml` records that Hyprland 0.57 ignores that until the surface is mapped, accepts input, and has alpha above zero. kuwai holds `systemd-inhibit --what=idle`, and `Idle.qml` also checks `Caffeine.on` directly, so the shell's own dim, lock, and sleep do not depend on the inhibitor. pocket-dots has no such switch. The 1×1 `rice-caffeine` carrier is the part Hyprland does not count. It still matches the `rice-*` blur rule. Harmless at one transparent pixel. It is not what keeps the machine awake.
- Turning caffeine on clears `Saver.screensOff` but does not send a DPMS enable. A key that toggles it usually wakes the panel first. An IPC toggle while the screens are already off does not.
- The screensaver's default is to run while caffeine is on. That is written down, and `docs/PLAN-kuwai.md` already notes a film decoded for hours on both screens. Caffeine keeps the machine awake. It does not keep a decoder cheap.

### What to adopt, now that the layers are known

1. A still-wallpaper change on a bottom layer that exists only during the change. Invisible hand-off, `sin(πt)` so both ends match, textures at screen size, a stats readout, and a fallback that actually sets the new image.
2. No blur and no compositor animation on that layer. Namespace outside `rice-*` and outside `quickshell*`.
3. Per-screen old image and per-screen crop, which pocket-dots does not do.

As of 2026-11-17 the hand-off is in `shell/services/WallFx.qml`, namespace `kuwai-wallfx`, with `shell/shaders/wallreveal.frag`. The new picture grows from the island. The order, the `sin(πt)` envelope, per-screen images, and a watchdog that sets awww itself are in that file. It is not their contagion map or their outline mode.
4. `rice-wallpaper` is now `kuwai-wallpaper`, outside the glass blur rule.
5. Coverage is the union of the windows, so overlaps are counted once.
6. Keep caffeine as it is: systemd-inhibit plus `Idle.held`. Do not replace it with caelestia's empty inhibitor. If the screens were forced off, turning caffeine on should DPMS them back on. A still, not a looping film, is enough for a night under caffeine.
