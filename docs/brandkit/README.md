# kuwai brand kit

**kuwai** is the desktop: Hyprland session (`hypr/`) + Quickshell shell (`shell/`). Both the product name and the CLI (`bin/kuwai`, `~/.local/state/kuwai`) use **kuwai**.

## Identity

- **Hook:** the flared top-edge island. No mascot.
- **Tone:** calm, plain, concrete; no loud chrome on the clock row.
- **One meaning per colour** (see [DESIGN.md](../DESIGN.md) and `shell/config/Theme.qml`): accent (`#0a84ff` or active theme) = selection; white = status; green (`#30d158`) = good/charging; orange (`#ff9f0a`) = attention/warning; red (`#ff453a`) = critical/error; yellow (`#ffd60a`) = search/Caffeine; purple (`#bf5af2`) = Focus/screen share.

## Assets

| Asset | Location |
| --- | --- |
| SVG marks (light, dark, app tile) | `docs/brandkit/assets/kuwai-mark.svg`, `kuwai-mark-dark.svg`, `kuwai-mark-tile.svg` |
| SVG horizontal wordmarks (light, dark) | `docs/brandkit/assets/kuwai-wordmark.svg`, `kuwai-wordmark-dark.svg` |
| Web/PWA mirrors | `site/public/assets/brand/` |
| UI tokens (colour, type, motion) | `shell/config/Theme.qml`, [DESIGN.md](../DESIGN.md) |
| Phosphor icons | `shell/assets/phosphor/` |
| Brand marks (agents/tools) | `shell/assets/brands/` (see [NOTICE.md](../../NOTICE.md)) |
| Media captures | `docs/media/` |

## Guidelines

- One interruption surface per event (peek, toast, or moment — not all three).
- Name the agent harness in approval alerts (Claude Code, Codex, T3 Code, kittymux, Cursor, Devin).
- Keep all UI colours inside `Theme` tokens (`bin/kuwai-tokens --check`).
