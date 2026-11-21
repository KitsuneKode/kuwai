# ADR-009: Typography, FreeType Rendering, and HyDE Interoperability

## Status
Accepted

## Date
2026-11-21

## Context
kuwai delivers an Apple-inspired typographic hierarchy on Linux while remaining
legally distributable and functional both alongside HyDE and standalone without
HyDE:

- Apple's SF Pro font license restricts distribution to Apple platforms, so
  kuwai cannot install or bundle SF Pro.
- Using the variable SF Pro font in Qt mapped separate instances per
  weight × size combination, consuming ~300 MB of shell memory.
- Qt's default distance-field glyph atlas corrupted glyphs (blank or
  overlapping labels) across multiple font weights/optical sizes.
- kuwai originally grew on HyDE (which writes hyprlang `theme.conf` /
  `colors.conf` and manages `awww-daemon` / Waybar), but must work cleanly on
  machines without HyDE and must never let HyDE export a hyprlang
  `HYPRLAND_CONFIG` on Hyprland 0.57 (which parses it as Lua and boots empty).

## Decision

1. **Typography and native text rendering (`install.sh`, `hypr/kuwai/look.lua`, `shell-auth/components/Label.qml`)**:
   - Depend on `inter-font` (OFL) and `ttf-nerd-fonts-symbols` (not `-mono`,
     whose family name `"Symbols Nerd Font Mono"` does not match what the shell
     requests).
   - Use SF Pro opportunistically only if the user already installed it
     (`SF Pro Text, Inter, sans-serif`); never install SF Pro in `install.sh`.
   - Select static optical cuts (`SF Pro Text` below 20 px, `SF Pro Display`
     at ≥20 px) rather than variable SF Pro to avoid the ~300 MB memory cost.
   - Render UI labels with `renderType: Text.NativeRendering` (FreeType) for
     crisper small text and zero distance-field atlas corruption.

2. **Single HyDE detection contract and theme interop (`lib/hyde.sh`, `hypr/kuwai/core.lua`, `hypr/kuwai/env.lua`, `hypr/kuwai/theme.lua`, `hypr/kuwai/hyde.lua`, `bin/kuwai-theme`, `bin/kuwai-themes`, `bin/kuwai-nohyde`)**:
   - Define HyDE presence uniformly across Lua, shell scripts, Python, and QML
     by the existence of `~/.local/lib/hyde/globalcontrol.sh`, with graceful
     non-HyDE fallbacks verified by `bin/kuwai-nohyde --strict`.
   - Always point `HYPRLAND_CONFIG` at `~/.config/hypr/hyprland.lua` so HyDE's
     switcher sees a readable path without breaking Hyprland 0.57's Lua parser.
   - Parse HyDE's `colors.conf` and `theme.conf` directly in `hypr/kuwai/theme.lua`
     with type coercion against live Hyprland option types, taking only plain
     appearance options (skipping rules, `exec`, `source`, and animations,
     which kuwai owns) and applying kuwai's identity layer last.
   - Start `awww-daemon` directly before HyDE's `wallpaper.sh` at login so the
     cached wallpaper appears immediately without a delayed pointer-grow flash.
   - When installing kuwai themes (`bin/kuwai-theme`), carry over the user's
     current GTK/icon/font settings and omit `waybar.theme` (the island is the
     bar).

## Alternatives Considered

- **Bundling or auto-installing SF Pro**:
  Rejected due to Apple's font license restrictions.
- **Using Qt distance-field text rendering with variable fonts**:
  Rejected due to ~300 MB RAM overhead and glyph-atlas rendering bugs.
- **Requiring HyDE or running HyDE's full hyprlang stack**:
  Rejected because Hyprland 0.57 uses Lua configs and kuwai must run cleanly
  without HyDE.

## Consequences
- Fresh installs without SF Pro or HyDE render cleanly using Inter and kuwai's
  own fallbacks with zero HyDE noise (`bin/kuwai-nohyde --strict`).
- Existing HyDE themes continue switching seamlessly via `hyprctl reload`.
