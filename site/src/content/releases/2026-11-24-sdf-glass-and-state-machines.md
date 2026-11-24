---
title: "Single-pass SDF glass, zero literal easings, pure state machines & 0/0/0 layers"
summary: "Compiled SDF GlassCard shader, 0 Hz FluidHighlight, pure .mjs reducers for overlays/settings/island/OSD, 74→0 literal easings, 9→0 layer leaks, and a zero-notice 138-frame visual gate."
date: 2026-11-24T17:00:00Z
category: "Craft & Architecture"
slugId: "sdf-glass-and-state-machines"
---

- **Single-pass SDF liquid glass:** Replaced multi-rectangle `GlassCard` layering with a compiled Qt 6 `ShaderEffect` (`glasscard.frag.qsb`) rendering base tint, 1 px outer dark ring, top-down sheen, bottom shade, directional top-left/bottom-right specular rim, and procedural grain in a single draw call.
- **Zero literal tokens & easings (`0 / 0 / 0 / 0 / 0`):** Migrated all 74 remaining raw Qt easings onto `Theme.easeOut`, `Theme.easeInOut`, `Theme.easeDrawer`, `Theme.easeSine`, and `Theme.easeIn`, and tightened `CalendarPanel` onto the `Theme` type scale for `138 frames · 0 wrong · 0 to look at`.
- **Pure `.mjs` state machines & zero component-to-service leaks (`0 / 0 / 0`):** Wired unit-tested reducers into `Center`, `AssistantOverlay`, `ClipboardPanel`, `Settings`, `IslandBar`, and `Osd`, eliminated all 9 `comp_imports_service` imports, fixed `Ui.Button` keyboard focus forwarding, and added keyring-first `secret-tool` lookup for T3 tokens.
- **Real idle budgets:** Replaced `FluidHighlight`'s always-on `FrameAnimation` with reactive ancestor/transform signals, gated 20 Hz peak monitoring while hidden/locked, switched `Updates` to `FileView` watching, gated optional daemons (`nm-applet`, `kuwai-feeds`), and added at-rest wakeup & dGPU checks to `bin/kuwai-check`.
