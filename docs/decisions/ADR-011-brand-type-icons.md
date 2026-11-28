# ADR-011: Brand, Bundled Type, Clock Type, Phosphor Icons, and the Glass Floor

## Status
Accepted

## Date
2026-11-28

## Context
ADR-009 made Inter the distributable default and used SF Pro only when the
owner had already installed it. That kept the shell legal, but it gave machines
without SF Pro a different voice from kuwai's brand, made the rounded clock
opportunistic rather than designed, and left the icon system with six font
files plus an asynchronous 73 KB JSON parse before names could resolve.

The brand system also existed as hand-edited SVG copies. Small sizes, the
monochrome mark, the squircle tile and the outlined wordmark could drift apart
because there was no single deterministic source.

## Decision

1. **One deterministic brand generator (`bin/kuwai-brand`)**:
   - Draw the Machined Notch once in code and generate every static brand SVG
     from it: dark, light, monochrome, 16 px, 32 px, squircle tile, wordmark,
     aliases and hicolor icons.
   - Outline the wordmark from Geist SemiBold so distributed SVGs contain no
     text elements and never depend on the viewer's fonts. The circular i
     tittle is geometry matching the notch dot.
   - Keep `--check` deterministic: generated files either match byte for byte
     or the test suite fails.

2. **Bundled Geist as the universal default (`shell/assets/fonts/`, `shell/config/Fonts.qml`)**:
   - Bundle static Geist 400/500/600/700 and Geist Mono 400/500 under the SIL
     Open Font License, with each weight separated into its own family so Qt
     never instantiates one variable font once per weight × size combination.
   - Resolve `fontProfile: auto` as SF Pro Rounded when SF Pro Rounded and SF
     Pro Text are installed, otherwise SF Pro when Text and Display are
     installed, otherwise bundled Geist. Explicit `sf-rounded`, `sf`, `geist`,
     `inter` and `system` profiles remain live settings.
   - Keep SF Pro unbundled and uninstalled by kuwai. Its use is still strictly
     opportunistic, as ADR-009 required.
   - Use Geist's own four-point tracking curve, Apple's SF tracking tables on
     SF profiles, `Font.PreferVerticalHinting` for proportional labels, and a
     mono binding tied to the selected profile with SF Mono, Geist Mono,
     JetBrains Mono, Maple Mono and Iosevka choices.

3. **An anchored clock (`shell/components/ClockFace.qml`)**:
   - Set hours and minutes as separate anchored labels around a fixed colon
     raised by `-0.04em`; minute changes cannot move the colon.
   - Use SF Pro Rounded on SF clock faces and Geist 600 with `-0.045em`
     tracking on Geist. The clock face remains a live setting.

4. **Synchronous, lean Phosphor icons (`bin/kuwai-gen-icons`, `shell/config/icons.mjs`, `shell/config/Icons.qml`)**:
   - Generate `icons.mjs` deterministically from the Phosphor map and resolve
     it synchronously at startup; incomplete duotone pairs fall back to the
     regular outline rather than drawing half a duotone.
   - Keep the four semantic fonts: Regular, Bold, Fill and Duotone. Thin and
     Light are removed rather than kept resident for styles the design system
     does not use.
   - Auto icons are Bold at 16 px and smaller and Regular at 18 px and larger;
     active states crossfade to Fill; heroes, tiles and empty states opt into
     Duotone. `icon`/`iconStyle` are additive APIs, so existing `glyph` callers
     keep their Nerd Font fallback unchanged.
   - Ship a verified `nerdToPhosphor` compatibility table for common shell
     chrome glyphs and the `;` picker/custom capsule migration path.

5. **A legible glass floor (`shell/config/Theme.qml`)**:
   - Raise the base glass tint from 58% to 74% so toasts, OSD and notification
     cards remain legible over white windows. Elevated glass remains 74% and
     island glass remains 84%.

## Supersedes
This decision supersedes ADR-009's font-default and icon-loading choices:
Inter is now an explicit profile rather than the universal default, and the
asynchronous Phosphor JSON map is replaced by the generated synchronous
module. ADR-009's HyDE interoperability decisions and its prohibition on
bundling SF Pro remain in force.

## Consequences
- Machines without SF Pro still render the intended brand voice because Geist
  is part of the shell and licensed for redistribution.
- Owners with SF Pro Rounded get the Apple-like rounded UI and clock without
  manual font plumbing, while every profile can be changed live in Settings.
- Icon lookup is available before the first frame, icon memory drops by the
  Thin and Light font payloads, and component callers can migrate from private
  use glyphs to semantic Phosphor names incrementally.
- Brand assets can be regenerated and verified rather than reviewed as
  hand-maintained copies.
