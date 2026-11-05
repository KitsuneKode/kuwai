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
| UI tokens (colour, type, motion) | `shell/config/Theme.qml`, [DESIGN.md](../DESIGN.md) |
| Phosphor map (island glyphs) | `shell/assets/phosphor/` |
| Greeter / lock art | `greeter/`, `shell/modules/lock/` |
| Manual diagrams | `docs/media/` |

Add exported logos or wordmarks here under `docs/brandkit/assets/` when you have them (SVG only; no raster mascots). Until then, the island shape and SF Pro stack *are* the brand.

## Do / don't

- **Do:** one interruption surface per event (peek, toast, or moment — not all three).
- **Do:** name the harness in agent alerts (Claude, Codex, T3, kittymux).
- **Don't:** red pills beside the clock for quota; don't duplicate Quattro's always-on usage bar.
- **Don't:** introduce new accent colours outside Theme tokens.
