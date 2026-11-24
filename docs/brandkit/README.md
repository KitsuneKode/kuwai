# kuwai brandkit

**kuwai** is the desktop: Hyprland session + Quickshell shell (the island, notifications, lock). The **`rice`** CLI and `bin/rice-*` tools are the control plane — keep those names in code and docs for commands; the product name people see is **kuwai**.

## Identity

- **Hook:** the island (notch / pill at the top). No mascot.
- **Tone:** calm, precise, Apple-adjacent motion; never loud chrome on the clock row.
- **One meaning per colour** (see [DESIGN.md](../DESIGN.md)): accent = selection; white = status; green = good; orange = attention; red = bad; yellow = search/Caffeine.

## Name usage

| Context | Use |
|---------|-----|
| README, manual, install | **kuwai** |
| Commands, IPC, state paths | `rice`, `~/.local/state/rice`, `org.freedesktop.Notifications` owner |
| Hyprland module | `kuwai.*` in Lua |
| Repo / GitHub | `kuwai` (this repository) |

## Assets

| Asset | Location |
|-------|----------|
| SVG brand marks (light, dark, app tile) | `docs/brandkit/assets/kuwai-mark.svg`, `kuwai-mark-dark.svg`, `kuwai-mark-tile.svg` |
| SVG horizontal wordmarks (light, dark) | `docs/brandkit/assets/kuwai-wordmark.svg`, `kuwai-wordmark-dark.svg` |
| UI tokens (colour, type, motion) | `shell/config/Theme.qml`, [DESIGN.md](../DESIGN.md) |
| Phosphor map (island glyphs) | `shell/assets/phosphor/` |
| Greeter / lock art | `greeter/`, `shell/modules/lock/` |
| Manual diagrams | `docs/media/` |

All brand marks live in `docs/brandkit/assets/` (SVG only; no raster mascots) and mirror into `site/assets/brand/` for web, PWA, and Open Graph surfaces. The continuous-ear Dynamic Island silhouette with a single amber attention dot and Inter / SF Pro typography *are* the brand.

## Do / don't

- **Do:** one interruption surface per event (peek, toast, or moment — not all three).
- **Do:** name the harness in agent alerts (Claude, Codex, T3, kittymux).
- **Don't:** red pills beside the clock for quota; don't duplicate Quattro's always-on usage bar.
- **Don't:** introduce new accent colours outside Theme tokens.
