# Premium Kuwai — Brand System, Shell UI Polish, Sweep Island Panel & Site Refresh

Status: planned (Phase 1 design — awaiting owner approval before Phase 2 implementation)
Scope: brand, typography, icons, shell UI, sweep island (Path A now / Path B later), site
Created: 2026-11-27
Updated: 2026-11-27

---

## 0. Executive Summary & Owner Decisions

This Phase 1 plan establishes a cohesive, premium design and engineering specification across four connected areas of **kuwai** (`KitsuneKode/kuwai`):

1. **Brand system** — replace the fragile double-stroke notch mark and live-`<text>` wordmark with **Direction 1: Machined Notch** (outlined SVG paths, monochrome, 16 px optical favicon, 512 px app icon), standardize on a **SIL OFL 1.1** bundled type triad (**Geist** UI + **Instrument Sans** Display + **Geist Mono** Mono) matching `sweep`, and unify 100 % of shell UI chrome on **Phosphor Icons (MIT)** (retiring 136 `Symbols Nerd Font` codepoint escapes from UI chrome and trimming 1.07 MB of unused font weights).
2. **Shell UI polish** — 18 concrete, evidence-backed fixes across all eight surfaces (Island, Control Center, Launcher, Notifications, OSD, Settings, Lock, Greeter), ranked by impact and effort, grounded in exact `file:line` citations.
3. **Sweep island panel (Path A now, Path B later)** — implement Path A first: a thin rendering-only QML panel (~150 lines) reading `sweep widget --json` (per `KitsuneKode/sweep#147` + all four review findings) and passive cache/receipt files via `FileView`, never deleting, never polling while closed, launching fixed absolute-path `sweep ui ...` argv through `Apps.run`, and retiring `bin/kuwai-sweep` and `sweepModel.js` while keeping `Island.open("sweep")`, the `sweep` IPC target, and settings keys working. Document the full Path B architecture, risks, and a safer declarative-JSON middle option (Path B-Lite) for later.
4. **Kuwai website (`site/`)** — refresh with the new brand kit, self-hosted OFL fonts (zero Google Fonts RTT), dedicated `/island/` and `/extending/` pages, Sweep showcase, zero-CLS media, and structured SEO metadata.

### Design Skills Applied (`aiforui.dev/skills`, `~/.agents/skills/`, `.claude/skills/`)

| Skill | Where applied in this plan | Concrete rule enforced |
| --- | --- | --- |
| `kuwai-ui` | Every QML surface, token ratchet, idle cost | Keep all tokens in `Theme.qml` (`kuwai-tokens --check`), 0 % idle CPU, `setpriv --pdeathsig KILL`, `Label` everywhere, no `data` property on Items. |
| `verify-kuwai` | Preview & test gates | Never touch the live shell (`~/.local/share/kuwai`) or user input; verify with isolated `qs -p <tmpdir>` and `bin/kuwai-rehearse --gate`. |
| `apple-design` | Notch morph, springs, translucency, reduced motion | Velocity-preserving springs (`surfaceIn`/`surfaceOut`), symmetric top-edge entry/exit, rubber-banding at boundaries, `reduceMotion` keeps fades only. |
| `emil-design-eng` | Animation frequency gate, curves, press feedback | Zero entrance animation on 100+/day keyboard actions (`Super+A` Launcher); `cubic-bezier(0.23, 1, 0.32, 1)`; press scale `0.97` (`>= 0.95` floor); never `scale(0)`. |
| `tactile-design` | Surface hierarchy, button roles, contrast, dark elevation | One primary action per surface; destructive never primary; dark elevation via step shift + structural hairline + 1 px crisp black drop (no glowing top bevels). |
| `fluid-functionalism` | Spring tiers, concentric radii, zero-shift active tabs | Three spring tiers (`springFast`/`Moderate`/`Slow`); `outer = inner + inset` radii; reserve semibold width in `Segmented` so active tabs never shift neighbours. |
| `make-interfaces-feel-better` | Optical alignment, icon weights, tabular numerals, hit targets | Match icon stroke to text weight (Regular 1.5 px / Bold 2 px), 1 px pure-white `ImageEdge` on dark media, `tabular-nums` on every live value, >= 40 px dense hit areas. |
| `better-typography` | Bundled SIL OFL type system & Linux FreeType rendering | Intentional Display/UI contrast (avoid two near-identical sans-serifs), >= 400 weight below 18 px, unitless leading, proper `font.variableAxes` gating. |
| `better-colors` | Contrast gates, semantic separation, C+ data hues | One meaning per colour (`>= 15°` OKLCH hue separation), `Theme.contrastInk()` on every colored disc/button, measured WCAG >= 4.5:1 text contrast. |
| `choreograph` | Panel open/close & view-swap sequencing | One entrance per container (notch leads, content fades once together); exits faster and simultaneous; no per-row stagger in high-frequency lists. |
| `animate` & `transitions-polish` | Individual transition timing & asymmetry | Close faster than open (`exitMs` < `enterMs`), hover wash in `80 ms`, sweep/progress tied to real events only. |
| `animation-performance` | GPU layers, `layer.enabled`, battery guards | Animate transform/opacity only; never hold permanent full-screen `layer.enabled: true` FBOs; gate ambient loops on `UPower.onBattery` and window visibility. |
| `interaction-design` | Loading skeletons, empty/error states, focus visibility | Layout-preserving skeletons after 150 ms (Launcher `+` / `fd`), immediate tick on copy with no toast, consistent `FocusRing` matching host corner radius. |
| `frontend-design` & `hallmark` | Kuwai website (`site/`) redesign & prototypes | Token-only CSS (`:root`), `overflow-x: clip`, no eyebrows or tracked-caps labels, `minmax(0, 1fr)` image tracks, authentic live captures, hero above the fold at 1280×800. |

---

## 1. Brand Audit & Proposal

### 1.1 Audit of Current Brand Assets

| Asset | Current state (repo evidence) | Findings / Deficiencies |
| --- | --- | --- |
| **Standalone mark** | [kuwai-mark.svg](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/docs/brandkit/assets/kuwai-mark.svg) & [kuwai-mark-dark.svg](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/docs/brandkit/assets/kuwai-mark-dark.svg) | Line 13 contains a backtracking path (`...36 26.5 36H21.5C28.956...`) that doubles back over itself at the bottom edge. Dark and light variants have different silhouettes (light adds a full-width top bar, dark uses a double translucent rim). The mark occupies only `y=13..33` (42 % of the 48 px height). At 16 px, the 1.5 px gradient stroke vanishes and the 2.25 px amber dot collapses below 1 px. No single-color monochrome (`currentColor`) SVG exists. |
| **Wordmark** | [kuwai-wordmark.svg](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/docs/brandkit/assets/kuwai-wordmark.svg) | Uses live `<text font-family="Inter, -apple-system, ...">kuwai</text>` instead of outlined `<path>` geometry. Renders with broken fallback fonts and distorted kerning (`letter-spacing="-1.1"`) on GitHub, Linux image viewers, and any browser without local Inter. |
| **App icon** | [kuwai-mark-tile.svg](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/docs/brandkit/assets/kuwai-mark-tile.svg) | Generic blue-tinted dark tile with oversized amber radial halo; weak silhouette separation against dark desktop docks/app grids. |
| **Type system** | [Theme.qml:401-489](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/shell/config/Theme.qml#L401-L489), [BaseLayout.astro:104](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/site/src/layouts/BaseLayout.astro#L104) | Shell prefers Apple's non-distributable **SF Pro** (`510`/`590` weights) over **Inter** (`inter-font`), while checking `hasFont("Inter Display")` which Arch's `inter-font` 4.x exposes as `Inter 28pt` (causing unexpected variable fallback). `Theme.qml:434` prefers `SF Mono → Geist Mono`, while `site/` loads Google Fonts `Inter + JetBrains Mono` — fragmenting the shell, the website, and `sweep` (which uses **Geist** and **Geist Mono**). |
| **Icon system** | [Icons.qml](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/shell/config/Icons.qml), [Icon.qml](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/shell/components/Icon.qml), `shell/` grep | **Split system:** `Theme.fontGlyph` (`Symbols Nerd Font`, raw `\u{f0...}` escapes) appears **136 times** across core UI primitives (`Button`, `Notice`, `ControlTile`, `Osd`, `Launcher`, `Settings`, `IslandRest`), while bundled **Phosphor Icons** (3.1 MB across 6 TTFs loaded at every startup!) are used only **39 times** (37 of them in `modules/assistant/`). Mixed stroke weights and inconsistent bounding boxes force manual pixel-offset hacks (`SysMarks.qml:127`). |

### 1.2 Three Proposed Brand Directions

Visual comparison rendered in [01-brand-system.png](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/shots/01-brand-system.png).

| Dimension | **Direction 1: Machined Notch (Recommended)** | Direction 2: K-Notch Monogram | Direction 3: Split Capsule |
| --- | --- | --- | --- |
| **Logo Mark** | Sculpted single-pass superellipse notch with continuous Bezier shoulders (`k = 1.28`), wider hardware proportions filling ~76 % of viewBox width, recessed white activity pill + live amber indicator dot (`#ff9f0a`). Identical silhouette across dark, light, monochrome (`currentColor` even-odd cutout), 16 px optical favicon, and 512 px squircle app icon. | Geometric `K` carved inside a rounded notch container with accent dot in upper right. | Two-piece mark: main notch pill paired with a floating satellite accent capsule (`IslandSplit`). |
| **Wordmark** | Lowercase `kuwai`, outlined SVG paths from **Geist SemiBold (600)** at `-0.04em` tracking, optically aligned to notch baseline. | Lowercase `kuwai`, outlined SVG paths from **Inter Display SemiBold**. | Lowercase `kuwai`, outlined SVG paths from **Plus Jakarta Sans SemiBold**. |
| **Type System (all SIL OFL 1.1)** | **UI:** Geist (`wght` 400/500/600/700)<br>**Display / Lock / Hero:** Instrument Sans (`wght` 500–700, `wdth` 92–96)<br>**Mono:** Geist Mono (`wght` 400/500/600) | **UI:** Inter 4 (`Inter 18pt`)<br>**Display:** Inter Display (`Inter 28pt`)<br>**Mono:** IBM Plex Mono | **UI:** IBM Plex Sans<br>**Display / Numerals:** Plus Jakarta Sans<br>**Mono:** JetBrains Mono |
| **Icon System** | **Phosphor Icons (MIT)** — bundled TTFs trimmed to 4 weights (`Regular`, `Bold`, `Fill`, `Duotone`). | **Lucide (ISC)** — compiled font or SVG via `IconImage`. | **Material Symbols Rounded (Apache 2.0)** — variable `FILL`/`wght` font. |
| **Strengths** | Preserves Kuwai's core visual hook (the top-edge notch) while fixing every geometry & 16 px bug; 1:1 typographic consistency with `sweep`; Instrument Sans `wdth` axis gives unmistakable architectural lock clocks & hero figures; zero icon migration dependency risk (Phosphor is already bundled!). | High avatar recognition on GitHub/AUR; familiar Inter optical sizing. | Directly references `IslandSplit` capsules; warm display numerals. |
| **Tradeoffs** | Requires bundling Geist + Instrument Sans + Geist Mono TTFs (~950 KB total) in `shell/assets/fonts/`. | Loses the iconic top-edge notch silhouette; Lucide lacks native Duotone/Fill active states; diverges from `sweep`. | Two-piece gap crowds at 16 px favicon; IBM Plex Sans is wider in tight 460 px panels; Material variable font triggers Qt 6 glyph-cache RAM bloat (`Label.qml:27`). |

### 1.3 Why Direction 1 Is Recommended

1. **Mark & Wordmark Craft:** Keeps the signature flared top-edge island that makes Kuwai immediately recognizable on r/unixporn and Hyprland showcases, fixes the broken backtracking path, adds true single-color monochrome (`fill-rule="evenodd"`) and dedicated 16 px optical geometry (thicker stroke, enlarged pill + dot), and outlines the `kuwai` wordmark into `<path>` primitives so it never falls back to system fonts.
2. **Type System Technical Verification (Linux / Qt 6 / Bundling):**
   - **Licence:** Geist, Geist Mono, and Instrument Sans are all **SIL OFL 1.1**, allowing direct bundling in `shell/assets/fonts/` (loaded via `FontLoader` in a singleton or installed to `~/.local/share/fonts/kuwai/` by `install.sh`) and self-hosting as WOFF2 in `site/public/fonts/`. No Apple SF Pro licence conflict; `KUWAI_FONT=geist|inter|sf|system` remains an opt-in override.
   - **Ecosystem consistency:** Aligns Kuwai's shell and website directly with `sweep` (Geist + Geist Mono).
   - **Deliberate Display pairing:** Pairing **Geist** (UI text) with **Instrument Sans** at slightly condensed display width (`wdth: 92` for the 150 px lock clock, `wdth: 96` for hero storage/telemetry figures and site H1/H2) avoids the "two near-identical sans-serifs" defect (`better-typography`) while replacing Apple's `SF Pro Rounded` with an authentic OFL display voice.
   - **Glyph coverage:** Geist covers full Latin, Latin Extended, Cyrillic, currency, arrows, and math symbols; Instrument Sans covers ~390–407 Latin/Latin-Extended languages; Geist Mono covers full Latin Extended + box-drawing/CLI glyphs with slashed zero (`zero`).
   - **Linux hinting & Qt 6 performance:** Standard TrueType outlines render crisply under FreeType (`Text.NativeRendering`) at 11–14 px. Ship **static weight cuts** (`400`, `500`, `600`, `700` for Geist; `400`, `500`, `600` for Geist Mono; `600`, `700` for Instrument Sans Display — or single bounded `wdth` instance) in QML rather than mapping an unbounded variable font across dozens of `(opsz, wght)` pairs, avoiding the ~300 MB Qt 6 glyph-atlas bloat documented in `Label.qml:27`.
   - **Tabular figures:** All three families ship native OpenType `tnum` (`Theme.featTabular`) so clocks, percentages, byte counts, and countdowns never jitter.
3. **Icon System Technical Verification (Phosphor TTF vs SVG `IconImage`):**
   - **Why bundled Phosphor TTF over per-icon SVG `IconImage`:** Kuwai renders 40–80 UI chrome icons simultaneously across the island, hover glance, control center, launcher, and notifications. Bundled Phosphor TTFs rendered via `Text { renderType: Text.NativeRendering }` share one glyph atlas, support instant zero-cost `color` tinting and `ColorAnimation` (no QtSvg re-rasterization per colour/theme switch), support animated Duotone opacity crossfades (`Icon.qml:27-45`), and add zero filesystem stat overhead. `IconImage` stays reserved strictly for freedesktop `.desktop` application icons (which are full-colour external rasters/SVGs).
   - **Memory optimization:** `shell/config/Icons.qml` currently loads all 6 Phosphor TTFs (3.1 MB). Removing unused `Phosphor-Thin.ttf` (535 KB) and `Phosphor-Light.ttf` (536 KB) and keeping **4 semantic weights** saves **1.07 MB** while establishing a strict visual grammar:
     - `regular` (1.5 px optical stroke) — resting 16–18 px UI chrome beside 400/500 text.
     - `bold` (2.0 px optical stroke) — dense 12–14 px island rest marks, status bar icons, and semibold buttons.
     - `fill` — active/selected state targets (toggled tiles, pinned items, active tabs).
     - `duotone` (20 % fill + crisp outline) — section headers, empty states, notice badges, and Control Center tiles.
   - **Fallback policy:** `Symbols Nerd Font` (`Theme.fontGlyph`) is retired from all Kuwai UI chrome and downgraded to an optional package used *only* for the Launcher `;` glyph picker and user-authored `kuwai capsule --glyph` / search-provider manifests (falling back gracefully to a Phosphor `sparkle` / `terminal` icon if absent).

### 1.4 Brand Asset Deliverables (Phase 2)

| File (in `docs/brandkit/assets/`, mirrored to `site/public/assets/brand/`) | Purpose |
| --- | --- |
| `kuwai-mark.svg` | Full-colour dark-surface notch mark (48×48 viewBox, single continuous path) |
| `kuwai-mark-light.svg` | Light-surface notch mark (same geometry, dark fill + white pill + amber dot) |
| `kuwai-mark-mono.svg` | Single-colour `currentColor` cutout mark (`fill-rule="evenodd"`) for themes/badges/terminal |
| `kuwai-mark-16.svg` | Optical 16×16 favicon & compact UI mark (heavier stroke, enlarged aperture) |
| `kuwai-mark-tile.svg` | 512×512 squircle app icon (`icon-192.png`, `icon-512.png`, `icon-maskable-512.png`) |
| `kuwai-wordmark.svg` / `kuwai-wordmark-light.svg` | Horizontal lockup with **outlined SVG paths** (zero `<text>` fallback risk) |

---

## 2. Shell UI Audit (All 8 Surfaces, Ranked by Impact & Effort)

Audited across all 231 QML files in `shell/` and `greeter/`, covering **Island**, **Control Center**, **Launcher**, **Notifications**, **OSD**, **Settings**, **Lock**, and **Greeter**.

### 2.1 Quantitative Baseline (Measured Today)

- `Theme.fontGlyph` (Nerd Font raw codepoints): **136** call sites vs **39** Phosphor `Icon` call sites.
- `docs/design/tokens-baseline.json`: **146** literal sizes, **147** literal radii, **18** literal durations (`0` raw hex/easings).
- Raw `Qt.rgba(...)` outside `Theme.qml`: **175** occurrences.
- `layer.enabled` usages: **27** (including permanent full-screen FBOs on Lock/Greeter and `layer.samples: 4` MSAA layers).
- `Animation.Infinite` loops: **33** (several unguarded against `UPower.onBattery` or unfocused inputs).
- Direct `font.variableAxes` overrides bypassing `Theme.axesFor()`: **5** surfaces (`Osd`, `Settings`, `Launcher`, `Clipboard`, `CenterContent`).

### 2.2 Ranked UI Fix List (Top 18 — Top 15 Highlighted for Phase 2)

| Rank | Impact | Effort | Surface(s) | Exact Location | Before (Current Defect) | After (Premium Fix) | Principle / Why |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| **1** | High | Med | All 8 surfaces (UI primitives) | `shell/components/ui/{Button,Notice,ControlTile,Chip}.qml`, `RaisedButton.qml`, `Segmented.qml`, `Osd.qml`, `IslandRest.qml`, `LauncherPanel.qml`, `SettingsPanel.qml`, `PasswordPill.qml` (136 sites) | Raw `\u{f0...}` `Theme.fontGlyph` Nerd Font escapes mixed beside 39 Phosphor icons; 6 Phosphor TTFs loaded (3.1 MB); optical offset hacks (`SysMarks.qml:127`). | Migrate all UI chrome to `Icon { name; style }` on bundled Phosphor (4 weights: Regular/Bold/Fill/Duotone, saving 1.07 MB); add `icon:` prop to `Button`, `Notice`, `ControlTile`, `Chip`. | `make-interfaces-feel-better` (stroke-to-weight parity, single icon grammar), `kuwai-ui` (memory & clarity). |
| **2** | High | Low | OSD, Settings, Launcher, Center, Clipboard | `Osd.qml:844-987`, `SettingsPanel.qml:163`, `LauncherPanel.qml:627`, `CenterContent.qml:107`, `ClipboardPanel.qml:1076` | Five surfaces hardcode `font.variableAxes: ({ "opsz": ..., "wght": ... })` bypassing `Theme.axesFor()`. `Osd.qml` uses 4 bare `Text` blocks with fixed `14`/`13` px, completely ignoring `Settings.textScale`! | Replace `Osd.qml` text blocks with `Label` (`Theme.sp()` container heights); route all `TextInput` fonts through a shared `SearchField` component using `Theme.axesFor()` + bundled Geist static cuts. | `better-typography` (dynamic type scaling & no variable-font synthesis bugs), `kuwai-ui`. |
| **3** | High | Low | Type & Theme Engine | `shell/config/Theme.qml:413-443` | Checks `hasFont("Inter Display")` (which Arch `inter-font` 4.x exposes as `Inter 28pt`), sets non-standard Apple weights `510`/`590`, and defaults to non-distributable SF Pro. | Bundle **Geist**, **Instrument Sans**, and **Geist Mono** (SIL OFL 1.1) as default (`KUWAI_FONT=geist\|inter\|sf\|system`), normalize weights to `400/500/600/700`, map display/lock numerals to Instrument Sans (`wdth: 92–96`). | `better-typography`, brand unity with `sweep`, zero Apple licence entanglement. |
| **4** | High | Low | Control Center, FocusRing, Inputs | `ControlTile.qml:66`, `RaisedButton.qml:104`, `SettingsPanel.qml:159`, `CenterContent.qml:102`, `ClipboardPanel.qml:1073,1360`, `QuickLook.qml:173,208`, `LauncherPanel.qml:629` | `ControlTile` checks `tile.tone === Theme.yellow` instead of `Theme.contrastInk(tile.tone)` (fails contrast on bright theme accents like `#66c7ff`). `RaisedButton` puts a `cornerRadius: 10` focus ring around a pill (`radius: height/2`). Six inputs hardcode `Theme.blue` selection instead of `Theme.accent`. | Use `Theme.contrastInk(tile.tone)` in `ControlTile`; derive `FocusRing` radius from `height / 2` on pills; standardize `selectionColor: Qt.alpha(Theme.accent, 0.45)` and `Theme.focusRing` token across all inputs. | `better-colors` (WCAG >= 4.5:1 on every theme), `tactile-design` (consistent focus geometry). |
| **5** | High | Med | Sweep Panel & Cleanup | `bin/kuwai-sweep`, `Sweep.qml`, `sweepModel.js`, `SweepPanel.qml` | Polls every 45 s / 300 s while closed; duplicates `summarize()` in Python; uses decimal `GB` vs binary `GiB`; launches via `Quickshell.execDetached` instead of `Apps.run`; lacks C+ dot-bar & Space view. | Replace with Path A thin QML renderer (`SweepPanel.qml` ~150 lines) + passive `FileView` watchers over `sweep widget --json`, `Apps.run` Kitty handoff, C+ dot-matrix bar, and `Projects \| Space` `Segmented`. | Owner decision (Path A), `kuwai-ui` (0 % idle CPU), `tactile-design` (no duplication/drift). |
| **6** | High | Med | Lock & Greeter | `LockView.qml:79,97,170`, `GreeterView.qml:135,182`, `PasswordPill.qml:149`, `LockCorner.qml:27`, `LoginWelcome.qml:25,33` | Permanent full-screen `layer.enabled: true` FBOs allocate tens of MB of VRAM per monitor; `LockView` (`Dates.shortDate`, tint `0.35`) and `GreeterView` (`Dates.longDate`, tint `0.22`) visually diverge; `PasswordPill` submit button scales to `0.90` on press (`< 0.95` floor). | Pre-blur wallpaper once via downscaled `sourceSize` and disable `layer.enabled` once blurred / when `opacity === 0`; unify Lock & Greeter date format + Instrument Sans clock + tint token; raise `PasswordPill` press scale to `0.96`. | `animation-performance` (VRAM / NVIDIA leak), `emil-design-eng` (`scale >= 0.95`), brand consistency. |
| **7** | High | Med | All Panels (Radii & Tokens) | `Notice.qml:22`, `SettingsPanel.qml:141`, `IslandHover.qml:84,119`, `SwitcherPanel.qml:72,94`, `UsagePanel.qml:224,397`, `Segmented.qml:25` (147 literal radii) | Ad-hoc radii (`9`, `10`, `13`, `14`, `Theme.r3 - 2`) break concentric nesting inside `NotchShape` (`30 px`) and `Card` (`Theme.r3 = 16 px`). | Compute nested radii via `Theme.innerRadius(outer, inset)` and snap all surfaces onto `r1/r2/r3/r4` (ratcheting `tokens-baseline.json` radii from 147 toward `< 30`). | `fluid-functionalism` & `make-interfaces-feel-better` (concentric radii). |
| **8** | High | Med | Control Center | `DisplayView.qml:151-250`, `ControlTile.qml:45-58` | Active `ControlTile` only lights the 34 px disc (card surface stays flat grey); brightness sliders show raw monitor model (`XV272U X1`); expanding Wi-Fi/BT drops the grid without an inline header/breadcrumb. | Add subtle active tone wash (`Qt.alpha(tone, 0.09)`) + tinted edge on active tiles; label monitors `External` / `Built-in` with model as subtitle (`docs/PLAN-design.md` #5); add crisp back-header strip on inline Wi-Fi/BT/VPN views. | `tactile-design` (scannable state + hierarchy), `apple-design` (wayfinding). |
| **9** | Med | Low | Segmented Control | `Segmented.qml:22-25,176` | Switching `weight: opt.on ? wSemibold : wRegular` widens the active label and triggers `measureLater()` + `placeLater()` reflow on every click; mixes `Layout.*` with caller `x`/`y` placement. | Reserve bold advance width with an invisible semibold ghost `Label` inside each segment (`opacity: 0`) so tab width is 100 % invariant on selection; use `Theme.r2` radius token. | `fluid-functionalism` (zero-shift weight transitions). |
| **10** | Med | Low | Notifications (Toasts) | `NotifCard.qml:116-119`, `Popups.qml:158` | `Behavior on height` lacks `enabled: !Theme.reduceMotion` (animates layout height even under reduced motion); raw durations `500` and `200` bypass `Theme` tokens; 3 fanned toasts can clip on short/scaled displays. | Gate `Behavior on height` on `!Theme.reduceMotion`, move `500`/`200` to `Theme.stackSinkMs`/`Theme.unmountMs`, and clamp fanned stack `maxHeight` against `Theme.screenSize(modelData, "height", 900) - reservedTop - 24`. | `apple-design` (reduced motion), `kuwai-ui` (token discipline). |
| **11** | Med | Low | Press Scale & Hit Targets | `Osd.qml:733,790`, `PasswordPill.qml:149`, `RestMark.qml:55`, `SysMarks.qml:104`, `Button.qml:54` | Press feedback varies from `0.90` to `0.98` across controls; small island badges lack consistent invisible hit-padding. | Introduce `Theme.pressScale: 0.97` (controls), `Theme.pressScaleRow: 0.985` (wide rows), `Theme.pressScaleSmall: 0.96` (compact discs >= 28 px; never `< 0.95`), and enforce `HoverHandler { margin: 6 }` on dense rest marks. | `emil-design-eng` & `make-interfaces-feel-better` (consistent tactile feel). |
| **12** | Med | Med | Launcher | `LauncherPanel.qml:45-59,178-200,620-650` | Async `fd` file searches and `+` Arch/AUR queries show empty/stale results with no loading indicator; mode prefixes (`=`, `!`, `+`, `:`, `;`) are invisible until typed; bare `TextInput` without shared `SearchField`. | Add inline mode pill chips (`= Calc`, `! Port`, `+ Pkg`, `: Emoji`) in search header; show layout-preserving `Skeleton` rows after 150 ms while `fd`/`+` runs; highlight active mode pill on prefix match. | `interaction-design` (perceived responsiveness & discoverability), `kuwai-ui` (loading skeletons). |
| **13** | Med | Med | Dark Surface Elevation | `Card.qml:34-44`, `ControlTile.qml:47-48`, `GlassCard.qml` | `Card.qml` paints a lit top-edge gradient while `RaisedButton.qml:54` forbids lit top edges and `ControlTile` omits the 1 px crisp black drop (`Theme.cardDrop`). | Unify dark surface grammar: drop `Card.qml`'s lit top hairline, give `ControlTile` the same subtle 1 px `Theme.cardDrop` + uniform structural `Theme.cardEdge` so every raised surface reads as one machined material. | `tactile-design` (never mix lit top bevels with flat dark rings). |
| **14** | Med | Low | Settings Panel | `SettingsPanel.qml:26,136-167` | Hardcoded `implicitHeight: 520` ignores screen height; sidebar search box (`32 px`, `radius: 9`) mismatches `CenterContent` (`36 px`, `Theme.r2`); global key-capture can collide with inline shortcut editors. | Clamp height to `Math.min(Theme.panelMaxH, Theme.screenSize(Screen, "height", 1080) - 120)`; replace custom search box with shared `SearchField` (`Theme.sp(36)`, `Theme.r2`); guard type-to-search when any child `TextInput`/shortcut capture has focus. | `kuwai-ui` (shared primitives & screen clamping), `tactile-design` (match the neighbour). |
| **15** | Med | Low | Battery & Idle Animations | `AmbientGlow.qml:18`, `SpringCaret.qml:27`, `IslandRest.qml:341,354,393,429`, `LinkRing.qml:26`, `QuickIcon.qml:77` | Continuous `Animation.Infinite` loops in `SpringCaret` and `IslandRest` breathing dots keep compositing on battery/unfocused windows; `LinkRing` & `QuickIcon` always force `layer.enabled: true; layer.samples: 4`. | Pause `SpringCaret` blink when window inactive or `UPower.onBattery` (solid caret); pause decorative breathing pulses on battery (static dot); replace MSAA `layer.samples: 4` with `Shape.CurveRenderer` (zero FBO allocation). | `animation-performance` & `kuwai-ui` (0 % CPU idle & battery stewardship). |
| **16** | Med | Low | Multi-Monitor & HiDPI | `Center.qml:107`, `IslandRest.qml:511`, `IslandHover.qml:167`, `LauncherPanel.qml:807` | `Center.qml:107` reads raw `shownScreen.width` without `Theme.screenSize()` guard; `IconImage` app icons omit `sourceSize` scaled by `Screen.devicePixelRatio` (blurry at 133 % / 200 % fractional scaling). | Route `Center.qml:107` through `Theme.screenSize(shownScreen, "width", 1920)`; bind `sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))` on every `IconImage`. | `kuwai-ui` (fractional HiDPI sharpness & output-change safety). |
| **17** | Low | Low | Notifications (Center) | `CenterContent.qml:58-63`, `NotificationsView.qml` | Tab badge counts all stored notifications even when filtered (`Unread`/`Important`), and some adapters repeat the app name in both header and title (`docs/PLAN-design.md` #3–#4). | Display `"3 of 13"` when a filter hides rows; strip redundant `"App: "` title/body prefixes inside notification adapters. | `tactile-design` (don't repeat what a heading says), `PLAN-design.md`. |
| **18** | Low | Low | Color Token Hygiene | 175 raw `Qt.rgba(...)` literals across `shell/` (`DiffView.qml`, `BellIcon.qml`, `SysMarks.qml`, `FocusRing.qml`) | Hand-typed `Qt.rgba(...)` tints and cutouts scatter across components, complicating high-contrast and light-accent adjustments. | Promote recurring semantic washes (`focusRing`, `cutoutRing`, `diffAddBg`, `diffDelBg`, `diffWarnBg`) into `Theme.qml` and extend `bin/kuwai-tokens` to track `Qt.rgba` ratchet. | `better-colors` (semantic tokens only in components). |

---

## 3. Sweep Island Panel — Path A Plan (Build Now)

### 3.1 Architectural Boundary (Path A)

Per owner decision (**Path A now, B later**):
- **`sweep` owns 100 % of domain logic**: scanning, rebuild-cost grouping (`cache`, `install`, `build`, `custom`), idle-day math, worktree state, binary IEC sizing (`KiB`/`MiB`/`GiB`), 11-category read-only Space overview, suggestion generation, atomic `0600` caching (`$XDG_CACHE_HOME/sweep/widget-v1.json`), passive live-apply progress (`$XDG_RUNTIME_DIR/sweep/active-apply.json`), and post-apply receipts (`$XDG_STATE_HOME/sweep/last-receipt.json`) via the read-only CLI `sweep widget [path] --json` / `--json-stream` / `--view projects|space` / `--cache-only` / `--refresh` specified in `KitsuneKode/sweep#147` (`.plans/kuwai-island.md`).
- **Incorporating all 4 review findings from `KitsuneKode/sweep#147`:**
  1. Always pass `--view <projects|space>` on `sweep widget` invocations so scans and cache entries match the active tab.
  2. Enforce clean grandchild termination for `sweep-engine`: `setpriv --pdeathsig KILL` covers `sweep`, and `sweep` itself must terminate `sweep-engine` on stdin EOF / `SIGTERM` / process-group teardown so closing the island or killing `sweep` never orphans `sweep-engine`.
  3. Keep `Space` review handoffs strictly aligned with `sweep ui` CLI flags (whitelisted intents only: `review_projects`, `review_space_developer`, `review_space_caches`, `review_space_trash`, `inspect_receipt` → fixed argv `["<abs-sweep>", "ui", <dir>, "--view", <view>]`).
  4. Consistent battery policy: when `UPower.onBattery` is true, **never auto-scan** — neither on stale cache **nor** on missing cache (first open on battery shows a quiet prompt + manual `Scan now` button so opening the island on battery never spikes disk/CPU).
- **`kuwai` owns only a thin rendering surface + passive file watchers**:
  - **Zero deletion capability** anywhere in Kuwai QML.
  - **Zero polling while closed** (no `Timer` spawning processes; `0 %` idle CPU).
  - **Fixed absolute-path argv only** launched via `Apps.run` (`shell/services/Apps.qml` → `systemd-run --user --slice=app.slice`) and `bin/kuwai-term`, so a shell restart never interrupts an active `sweep ui` terminal review.
  - **Reuses Kuwai primitives**: `NotchShape` (`Theme.panelM = 640 px`), `Segmented` (`Projects | Space`), `Ui.Notice` (at most 1 action), `Ui.EmptyState`, `Ui.Card`, `Ui.Button`, `Ui.Chip`, `FluidHighlight`, `Label`, `Icon` (Phosphor).

### 3.2 Files to Create / Update / Retire (Kuwai Side)

| Action | File | Responsibility & Size Budget |
| --- | --- | --- |
| **Replace** | `shell/services/Sweep.qml` | Thin singleton (~115 lines): locates absolute `sweep` binary once (`PATH`, `~/.bun/bin`, `~/.local/bin`, `/usr/local/bin`, `/usr/bin`); holds three passive `FileView` watchers (`widget-v1.json`, `last-receipt.json`, `active-apply.json`) + `sweep-viewed` threshold state; exposes `refresh(view, mode)` (spawns `setpriv --pdeathsig KILL -- nice -n 19 ionice -c3 <abs-sweep> widget <root> --view <view> --json-stream --resource-profile <low-memory\|balanced>` with 45 s / 120 s timeout & `SIGTERM` cancel on panel close); exposes `openReview(intent, path)` routing fixed argv through `Apps.run([Paths.bin + "/kuwai-term", "--title", "sweep", "--", absSweep, "ui", ...])`; preserves `IpcHandler { target: "sweep" }` (`open()`, `refresh()`). |
| **Replace** | `shell/modules/island/SweepPanel.qml` | Thin rendering-only panel (~150 lines): header with `Segmented` (`Projects \| Space`) + quiet `Rescan` & `Open TUI` `Ui.Button` icons; Instrument Sans hero + dim volume/guarded subline; embeds `SweepDotBar`; renders active state (`Ui.EmptyState` for not-installed / clean, `Ui.Notice` with <= 1 action for error / engine-missing / permission-denied / partial-receipt, `Ui.Card` suggestion + top 3 rows with `FluidHighlight`, single primary `Review in Sweep` `Ui.Button`, trust caption). Keyboard: `↑↓` rows, `←→` dot buckets, `Tab` Projects/Space, `Enter` open review, `Esc` close. |
| **Add** | `shell/components/SweepDotBar.qml` | Reusable 6-row Direction C+ dot-matrix bar + hover/keyboard legend (~85 lines), consuming C+ category arrays from JSON (`byCost` or `space.categories`), `Theme.wash(2)` unlit track, `Theme.hoverMs` (`80 ms`) dim on hover (`0 ms` on arrow keys), Phosphor icons, zero animations once settled. |
| **Add** | `shell/services/sweepFormat.mjs` | Tiny pure helper (~45 lines) strictly for binary IEC formatting (`B`, `KiB`, `MiB`, `GiB`, `TiB`), relative cache age (`3 h ago`), and capsule visibility threshold (`worthMark` / `isFresh` with 5 GiB step). Zero scanning or rebuild-cost logic. |
| **Update** | `shell/modules/island/CleanupPanel.qml` | Mount new `SweepPanel` in the `projects` tab (`tabLabel: "Sweep"` / `"Idle projects"`), keep `Island.cleanupView = "projects"` wiring intact so `Island.open("sweep")` continues working identically. |
| **Update** | `shell/modules/island/SysMarks.qml` & `IslandSplit.qml` | Update capsule to read binary `Sweep.compact` (`10.3 GiB`) and passive clearing status (`Clearing 3/12`) with Phosphor `broom` icon; keep `Island.preview("sweep")` and click-to-open. |
| **Update** | `shell/config/settings-schema.json` & `SettingsPanel.qml` | Keep existing keys **`sweepMark`** and **`sweepMinGB`** (zero breaking config migration!), update UI display copy from `GB` to `GiB` (and note `10 GiB` threshold). |
| **Retire (Delete)** | `bin/kuwai-sweep` (373 lines Python) | Fully replaced by `sweep widget --json` + `Apps.run` + `bin/kuwai-term`. |
| **Retire (Delete)** | `shell/services/sweepModel.js` (143 lines) | Legacy decimal-GB & artifact-kind splitter replaced by `sweepFormat.mjs` + Sweep JSON. |

### 3.3 Data Flow & State Coverage

```
Closed (at rest):
  [zero timers · zero processes]
  FileView (inotify) ──► $XDG_CACHE_HOME/sweep/widget-v1.json     (updates optional capsule if worth & +5 GiB)
                     ──► $XDG_RUNTIME_DIR/sweep/active-apply.json (shows "Clearing 3/12" capsule while user runs sweep ui)
                     ──► $XDG_STATE_HOME/sweep/last-receipt.json  (one-time green halo + receipt on next open)

Panel Open (Island.open("sweep") / Cleanup → Sweep):
  1. Synchronous cached paint from widget-v1.json (frame 1, zero skeleton flash)
  2. Check staleness + power:
     - No binary         ──► Ui.EmptyState ("Sweep is not installed" + copyable bun command)
     - Fresh (<= 30 min) ──► Settled Projects/Space card (zero process spawned)
     - Stale (> 30 min) or no cache:
         • AC power      ──► show cached snapshot + spawn single `sweep widget <root> --view <v> --json-stream --resource-profile low-memory`
         • On battery    ──► show `Cached · <age> · on battery` chip (or no-cache prompt) — NO auto-scan; wait for manual `Refresh`
  3. Panel Close / Stop click ──► SIGTERM in-flight widget process immediately
  4. User clicks `Review in Sweep` (or Enter on row) ──► Apps.run([kuwai-term, "--", absSweep, "ui", targetDir, ...]) → Island.close()
```

**Notice & Action Discipline (Kuwai rules):** Every error, partial-receipt, engine-missing, and permission-denied state renders in `Ui.Notice` with **at most one action button** (`Try again`, `Inspect in Sweep`, `Scan with fallback`, or `Open Settings`), never names a helper path or exit status (`REHEARSAL.md` `insides` gate), and never leaves a skeleton beside an error (`waits-forever` gate).

### 3.4 Test & Rehearsal Plan (Path A)

1. **Unit tests (`bun test`):** `tests/shell/sweep-format.test.mjs` covering binary IEC units (`0 B`, `410 MiB`, `57.4 GiB`, `1.2 TiB`), threshold & 5 GiB step gating, relative age strings, and strict argv whitelist builder (rejecting any non-whitelisted intent or relative path).
2. **Security & contract tests (`pytest`):** `tests/security/test_sweep_argv.py` verifying `Sweep.qml` uses `Apps.run` (never `Quickshell.execDetached`), uses `setpriv --pdeathsig KILL`, never calls `sweep apply`/`delete`/`rm`, and validates `widgetSchemaVersion === 1`.
3. **Rehearsal scenes (`tests/ui/scenes.json`):** Add scenes for `sweep/settled`, `sweep/scanning`, `sweep/stale-battery`, `sweep/empty-clean`, `sweep/receipt`, `sweep/partial-notice`, `sweep/error-notice`, `sweep/not-installed`, and `sweep/space-view`, gated by `bin/kuwai-rehearse --gate` at 100 %, 120 %, and 200 % text scale.
4. **Compatibility tests:** Verify `qs ipc -p <tmpdir> call sweep open`, `call sweep refresh`, `Island.open("sweep")`, and `Settings.sweepMark` / `Settings.sweepMinGB` in an isolated `qs -p <tmpdir>` instance.

---

## 4. Path B Later — Generic Island Plugin System

Once Path A is proven in production and Kuwai has a second or third external panel candidate, Kuwai can introduce a generic island plugin system. Below is the engineering design, effort estimate, security/stability risk analysis, and a **safer middle option (Path B-Lite)**.

### 4.1 Full Path B (In-Process QML Plugins)

- **Discovery (`bin/kuwai-ext panels`):** Scans `$XDG_CONFIG_HOME/kuwai/panels/<id>/manifest.json` (extending `docs/EXTENDING.md` alongside `providers` and `capsule`).
- **Versioned Host API (`import Kuwai.Plugin 1.0`):** A dedicated QML module exporting a frozen, read-only facade (`PluginHost`):
  - `theme` (token subset: colours, radii, type scale, spacing, `sp()`)
  - `ui` (`Button`, `Card`, `Notice`, `Chip`, `EmptyState`, `Segmented`, `Label`, `Icon`, `FluidHighlight`, `ScrollFade`, `ScrollHint`)
  - `env` (`reduceMotion`, `onBattery`, `textScale`, `highContrast`, `screenName`, `via`)
  - `actions` (`launchTerminal(argv, cwd)` checked against manifest `allowedCommands` + `Apps.run`, `openUrl(url)` checked by `Links.safeLink`, `copyText(s)`, `closeIsland()`, `openSettings(page)`).
- **Effort Estimate (Full Path B):** **Large (~3–4 weeks / 5 PRs)**
  1. `bin/kuwai-ext panels` validator + symlink/ownership test suite (~3 days)
  2. Versioned `import Kuwai.Plugin 1.0` QML module + `qmldir` + API stability tests (~5 days)
  3. `Plugins.qml` loader, `IslandBar` / `IslandSplit` mounting, crash-loop sentinel & `KUWAI_NO_PLUGINS=1` (~5 days)
  4. `kuwai plugins list|enable|disable|doctor` CLI + Settings UI (~4 days)
  5. Docs, rehearsal fault-injection fixtures, and migrating Sweep onto `Kuwai.Plugin 1.0` (~4 days).

### 4.2 Security & Stability Risks (Mandatory Mitigations for Path B)

| Risk | Why it matters | Required Mitigation |
| --- | --- | --- |
| **1. In-process QML is NOT a sandbox** | A QML component loaded via `Loader` executes inside `kuwai-shell.service`'s Qt/V8 engine with full user privileges: it can import `Quickshell.Io`, spawn arbitrary `Process` commands, read `~/.ssh`/`~/.config`, or monkey-patch singletons. | Document explicitly in `SECURITY.md` and `docs/EXTENDING.md` that QML plugins are **trusted local code** (like Hyprland or GNOME Shell extensions), never untrusted downloads. Require explicit user enablement (`kuwai plugins enable <id>`), never auto-load plugins dropped into `~/.config` without consent. |
| **2. Package-installed `moduleDir` ownership & symlink attacks** | A manifest pointing `moduleDir` at `/usr/share/sweep/quickshell/Sweep` (root-owned) or `~/.local/share/...` (user-owned) could be hijacked if any ancestor directory is group/world-writable or a symlink escapes `moduleDir`. | Extend `bin/kuwai-ext` `own_file`: require `moduleDir` and every `.qml`/`qmldir`/`.mjs` inside to be owned by `root` (`uid 0`) or `getuid()`, mode `& 0o022 == 0` on the target **and every parent directory**, reject any symlink whose `realpath` leaves `moduleDir`, and verify `qmlEntry` has no path traversal. |
| **3. Crash-loop bricking the desktop shell** | A segfault, infinite binding loop, or Qt 6.12 layer crash inside a plugin kills `kuwai-shell.service`; systemd restarts it every second into an infinite crash loop, locking the user out of their bar/lock UI. | Write `$XDG_RUNTIME_DIR/kuwai/plugin-boot/<id>.attempt` before `Loader.active = true` and clear it 10 s after `Loader.Ready`. If 2 consecutive attempts exist without a clean clear, auto-disable `<id>` in `plugins-disabled.json` and surface a single `Ui.Notice` ("Plugin disabled after crash · Re-enable in Settings"). |
| **4. Recovery kill switch** | Users debugging a broken upgrade or plugin conflict need a zero-config bypass. | Honour `KUWAI_NO_PLUGINS=1` in `Plugins.qml` (skips all plugin discovery and loading at startup) plus `kuwai start --no-plugins` and `kuwai plugins disable <id>`. |
| **5. API drift across Kuwai updates** | Direct imports of `qs.services` or `qs.components` break plugins whenever Kuwai renames internal files. | Enforce `hostApi: ">=1.0 <2.0"` check in `kuwai-ext panels`; expose only `import Kuwai.Plugin 1.0` and add a CI contract test guaranteeing no breaking removals inside `1.x`. |

### 4.3 Safer Middle Option: Path B-Lite (Declarative JSON Island Panels) — Recommended First Step Toward B

Before ever loading third-party QML in-process, Kuwai can ship **Path B-Lite (~1 week / 2 PRs)**, directly generalizing Path A's `sweep widget --json` contract:

- A plugin manifest in `~/.config/kuwai/panels/<id>/manifest.json` declares a read-only executable `command` (validated with `bin/kuwai-ext`'s existing `own_file` rule), optional `cacheFile` / `statusFile` watched via `FileView`, `panelWidth` (`panelS` / `panelM`), and a static `allowedActions` whitelist (`url` or fixed `argv` prefix).
- The plugin runs **out of process** (under `setpriv --pdeathsig KILL`, 2 s–45 s timeout, only when opened) and prints a versioned **Declarative Panel JSON (`kuwaiPanelSchema: 1`)** composed from Kuwai's own primitives:
  - `views`: optional `Segmented` tab list
  - `hero`: `{ value, label, sub, tone }`
  - `visualization`: `{ type: "dotBar" | "meter", buckets: [...] }`
  - `notice`: `{ tone, title, detail, actionId }` (strictly <= 1 action)
  - `card` / `rows`: `{ title, sub, items: [{ title, sub, badge, meta, actionId }] }`
  - `primaryAction`: `{ label, actionId }` + `trustCaption`
- **Why Path B-Lite wins for 90 % of integrations:** Zero untrusted QML in-process, impossible to crash `kuwai-shell.service`, automatic compliance with Kuwai's `Theme.qml`, `Text.NativeRendering`, `Settings.textScale`, `highContrast`, `reduceMotion`, and `REHEARSAL.md` gates, and ~3× smaller engineering & maintenance cost than Full Path B. Full QML plugins (Path B) remain an option only if a future plugin truly needs custom shaders or custom input widgets.

---

## 5. Kuwai Website (`site/`) Update Plan

Audited [BaseLayout.astro](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/site/src/layouts/BaseLayout.astro), [index.astro](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/site/src/pages/index.astro), [brand.astro](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/site/src/pages/brand.astro), and [global.css](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/site/src/styles/global.css).

### 5.1 Brand & Design System Refresh (`site/src/styles/global.css`, `BaseLayout.astro`, `brand.astro`)

- **Self-hosted OFL fonts:** Remove external `fonts.googleapis.com` / `fonts.gstatic.com` links from `BaseLayout.astro:102-104` (which currently load `Inter` + `JetBrains Mono` and incur extra DNS/TLS latency + third-party requests). Vendor subsetted Latin/Extended WOFF2 files in `site/public/fonts/` for **Geist** (`400`, `500`, `600`, `700`), **Instrument Sans** (`wdth` variable `600`–`700` for H1/H2/hero stats), and **Geist Mono** (`400`, `500`), preloaded via `<link rel="preload" as="font" type="font/woff2" crossorigin>`.
- **Logo & favicon refresh:** Replace `site/public/assets/brand/*` and `favicon.svg` / `favicon-32x32.png` / `apple-touch-icon.png` with Direction 1's outlined wordmarks, 16 px optical favicon, monochrome mark, and 512 px squircle app icon.
- **Upgraded `/brand/` page:** Showcase all 5 mark variants (dark, light, monochrome, 16 px optical, app tile) with one-click SVG downloads, live interactive Type System specimen (Geist / Instrument Sans / Geist Mono), Phosphor 4-weight icon grid, and semantic colour token swatches (`#66c7ff` Kuwai Night accent alongside semantic tokens).
- **Hallmark / Tactile refinement on `index.astro`:** Tighten hero copy so headline + 1 crisp sentence + install CTA + live island clip sit cleanly above the fold at `1280×800`; remove middle-dot-joined metadata eyebrows (`hero-kicker`) in favour of clean version/stack pills; add subtle `1 px` pure-white `ImageEdge` around all media frames.

### 5.2 New & Updated Pages

| Route | Purpose & Content |
| --- | --- |
| `/` (`index.astro`) | Refreshed hero with new Direction 1 wordmark + Instrument Sans display headline; updated Cleanup section highlighting the new Path A **Sweep** island panel (`sweep widget --json`, C+ dot bar, binary GiB, read-only Space overview); updated Requirements listing bundled Geist/Instrument Sans/Geist Mono & Phosphor (Nerd Font moved to Optional for `;` glyph picker). |
| `/island/` (New) | Dedicated deep-dive on Kuwai's signature top-edge island: Rest → Hover Glance → Expanded panels → Floating `IslandSplit` capsules → Live Activities (alarms, timers, agents, Sweep), with live 60 fps WebP clips and keyboard shortcut table. |
| `/extending/` (New) | User-facing guide mirroring `docs/EXTENDING.md`: Search Providers (`~/.config/kuwai/providers/`), Custom Capsules (`kuwai capsule set`), the Sweep integration contract (`sweep widget --json`), and the roadmap for Declarative JSON Island Panels (Path B-Lite) & versioned QML plugins (Path B). |
| `/brand/` (Updated) | Complete Direction 1 brand kit (marks, outlined wordmarks, 16 px favicon, type triad, Phosphor weights, semantic tokens). |
| `/changelog/` (Updated) | Release notes for the brand, UI polish, and Sweep Path A update. |

### 5.3 Performance & SEO Upgrades

- **Zero external requests & `CLS = 0`:** Self-hosted WOFF2 with `font-display: swap` + metric-adjusted fallback; explicit `width` and `height` attributes on every `<img>` across `index.astro`, `/island/`, and `/brand/`; `fetchpriority="high"` on hero media and `loading="lazy"` + `decoding="async"` below the fold.
- **Structured data & discovery:** Add `TechArticle` / `BreadcrumbList` JSON-LD on `/island/` and `/extending/`; update `SoftwareApplication` schema on `/` with refreshed `og-image.png` (1200×630 rendered in Direction 1 brand); add `/island/` and `/extending/` to `sitemap.xml` and `/llms.txt`; verify Lighthouse Performance/Accessibility/Best Practices/SEO >= 98 across desktop & mobile.

---

## 6. Prototypes & Rendered Screenshots (Phase 1 Artifacts)

All mocks are self-contained HTML files in `prototypes/premium-design/` with `1160×800` headless Chrome screenshots in `prototypes/premium-design/shots/`:

| # | Surface | HTML Mock | Rendered PNG Screenshot |
| ---: | --- | --- | --- |
| 1 | Brand System (3 Directions + Recommended Specimen) | [01-brand-system.html](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/01-brand-system.html) | [01-brand-system.png](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/shots/01-brand-system.png) |
| 2 | Island (Rest + Capsules, Hover Glance, Expanded Cards) | [02-island-states.html](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/02-island-states.html) | [02-island-states.png](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/shots/02-island-states.png) |
| 3 | Control Center & PipeWire Sound Mixer | [03-control-center.html](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/03-control-center.html) | [03-control-center.png](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/shots/03-control-center.png) |
| 4 | Launcher (`Super+A`, Mode Pills & Loading Skeleton) | [04-launcher.html](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/04-launcher.html) | [04-launcher.png](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/shots/04-launcher.png) |
| 5 | Sweep Panel — Projects View, Scanning, Stale Battery, Receipt | [05-sweep-projects.html](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/05-sweep-projects.html) | [05-sweep-projects.png](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/shots/05-sweep-projects.png) |
| 6 | Sweep Panel — Read-Only Space View, Notices & Empty State | [06-sweep-space-and-errors.html](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/06-sweep-space-and-errors.html) | [06-sweep-space-and-errors.png](file:///home/kitsunekode/.t3/worktrees/rice/t3-5147a7a0-3f0d9c7e5f82ff6f/prototypes/premium-design/shots/06-sweep-space-and-errors.png) |

---

## 7. Phase 2 Build Sequence (Starts Only After Owner Approval)

1. **PR 2.1 — Brand Kit, Bundled SIL OFL Fonts & Phosphor Icon Foundation:** Ship Direction 1 SVGs in `docs/brandkit/assets/`, bundle Geist / Instrument Sans / Geist Mono in `shell/assets/fonts/`, trim Phosphor to 4 weights in `Icons.qml`, update `Theme.qml` & `Label.qml`, add `icon:` prop to `Ui.*` primitives.
2. **PR 2.2 — Shell UI Polish (Top 15 Fixes):** Migrate 136 `fontGlyph` UI sites to Phosphor `Icon`, fix `Osd`/`Settings`/`Launcher`/`Center` `variableAxes` & `textScale`, fix `ControlTile` contrast & active wash, zero-shift `Segmented`, pill `FocusRing`, concentric radii ratchet, Lock/Greeter `layer.enabled` & visual unification, battery guards on infinite loops, HiDPI `IconImage` `sourceSize`.
3. **PR 2.3 — Sweep Island Panel (Path A) & Legacy Retirement:** Ship thin `Sweep.qml`, `SweepPanel.qml` (~150 lines), `SweepDotBar.qml`, `sweepFormat.mjs`; retire `bin/kuwai-sweep` and `sweepModel.js`; add unit/security/rehearsal scenes; verify `Island.open("sweep")`, `sweep` IPC, and `sweepMark`/`sweepMinGB` compatibility.
4. **PR 2.4 — Kuwai Website (`site/`) Refresh:** Apply new brand marks & self-hosted WOFF2 fonts, add `/island/` and `/extending/`, update `/` and `/brand/`, verify Lighthouse & `bun run build`.
5. **Verification Gate (every Phase 2 PR):** `pytest tests`, `bun test`, `lua tests/hypr/test_*.lua`, `bin/kuwai-tokens --check`, `bin/kuwai-comments --check`, `bin/kuwai-rehearse --gate`, and isolated `qs -p <tmpdir>` preview screenshots without touching the live shell.
