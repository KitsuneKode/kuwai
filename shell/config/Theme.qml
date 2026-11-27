// Design tokens for every surface in kuwai. The look is the glass HUD's:
// Hyprland blurs what is behind a layer, a dark translucent tint sits on top,
// text is SF Pro where installed (Text for UI, Display for large sizes,
// Rounded for numerals), else Inter, kuwai's shippable default (see Type
// below for how it is chosen). Glyphs come from Symbols
// Nerd Font. Motion is critically damped (no bounce): surfaces arrive fast
// and settle, and leave the way they came, a little quicker. See docs/DESIGN.md.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root
    // Accessibility (Settings → Accessibility): more contrast, less glass.
    readonly property bool contrast: Settings.highContrast
    readonly property real textScale: Math.max(1, Math.min(2, Settings.textScale || 1))
    // A length that holds text (a row's height, a column of figures, a day's
    // cell): it grows with Text size, as the text in it does. A fixed one cuts
    // or overlaps its text at 120 % (bin/kuwai-rehearse finds those).
    function sp(n) { return Math.round(n * textScale); }
    // ── Material ─────────────────────────────────────────────────────────
    // One glass, the voxtype HUD's: near-black #111114 over the compositor's
    // blur (components/GlassCard draws the ring, sheen and hairline).
    readonly property color glassTint: Qt.rgba(0.067, 0.067, 0.078, contrast ? 0.94 : 0.58)
    // Text-heavy cards (toasts) sit over anything: a little denser, so body
    // copy stays readable over busy windows.
    readonly property color glassTintThick: Qt.rgba(0.067, 0.067, 0.078, contrast ? 0.96 : 0.68)
    // Floating menus (the center, the island): the same glass, denser still,
    // with a deep shadow under it; it reads as raised, not as a lighter grey.
    readonly property color glassTintElevated: Qt.rgba(0.067, 0.067, 0.078, contrast ? 0.97 : 0.74)
    // The island's material, for the surfaces that belong with it (the
    // notification center, toasts): near-black, a little see-through so the
    // blur behind still reads on a large surface. One object, one material.
    readonly property color glassIsland: Qt.rgba(0.02, 0.02, 0.027, contrast ? 0.98 : 0.84)
    readonly property color notchGlassMid: Qt.rgba(0.024, 0.024, 0.031, contrast ? 0.97 : 0.86)
    readonly property color notchGlassBottom: Qt.rgba(0.035, 0.035, 0.045, contrast ? 0.96 : 0.78)
    readonly property color platter: Qt.rgba(1, 1, 1, 0.15)
    readonly property color platterDim: Qt.rgba(1, 1, 1, 0.08)
    readonly property color track: Qt.rgba(1, 1, 1, 0.18)
    readonly property color fill: Qt.rgba(1, 1, 1, 0.96)
    readonly property color fillDim: Qt.rgba(1, 1, 1, 0.32)
    readonly property color pill: Qt.rgba(1, 1, 1, 0.12)
    readonly property color pillHover: Qt.rgba(1, 1, 1, 0.22)
    // Hover on what has no surface until the pointer arrives: a list or menu
    // row, and a glyph button on the glass. One step each, shell-wide.
    readonly property color rowHover: Qt.rgba(1, 1, 1, 0.06)
    readonly property color ghostHover: Qt.rgba(1, 1, 1, 0.1)
    // A tile that always shows its surface (a suggestion, a control, a
    // device, a command), at rest and under the pointer.
    readonly property color tileRest: Qt.rgba(1, 1, 1, 0.065)
    readonly property color tileHover: Qt.rgba(1, 1, 1, 0.1)
    // Grouped content inside a panel (components/ui/Card): a whisper of a
    // surface and a hairline, so cards separate without boxes everywhere.
    readonly property color card: Qt.rgba(1, 1, 1, 0.05)
    readonly property color cardEdge: Qt.rgba(1, 1, 1, contrast ? 0.22 : 0.05)
    readonly property color cardDrop: Qt.rgba(0, 0, 0, 0.5)    // the 1 px drop under a Card: it reads as sitting on the panel
    // The glass's own near-black (glassTint's colour, opaque): dark ink on a
    // light fill, and the base an opaque tag mixes its tone into.
    readonly property color glassBlack: "#111114"
    // The glass made opaque, where nothing is behind to blur (the gallery,
    // a settings preview rendered as a picture).
    readonly property color glassSolid: "#1c1c1f"
    // A menu drawn over a panel (components/ui/ContextMenu): opaque, since the
    // rows under it would read through glass, and one step lighter than the
    // panel so it stands on it; its edge is a structure line you can see.
    readonly property color menuSurface: glassSolid
    readonly property color menuEdge: Qt.rgba(1, 1, 1, contrast ? 0.3 : 0.12)
    // The island's black, for the ring that cuts a badge out of what it
    // overlaps (a status dot on an app icon).
    readonly property color cutout: "#000000"
    // The desktop's own ground where there is no wallpaper: Hyprland's
    // background (hypr/kuwai/look.lua background_color). What stands in for a
    // missing wallpaper (the lock, the login opening into the desktop, a
    // wallpaper changing) is this, not pure black.
    readonly property color desktop: "#0b0b0f"
    // A round grey button on black (iOS's stop ✕): rest and hover.
    readonly property color knob: "#3a3a3c"
    readonly property color knobHover: "#4a4a4e"
    readonly property color chip: Qt.rgba(0.11, 0.11, 0.12, 1)   // an opaque disc on black (stacked logos)
    readonly property int statRingSize: 40   // the hover view's rings (machine and agents)
    readonly property int cardRingSize: 44   // a ring with its number in a card (a device's battery); StatRing's default
    // Agents' own colours (T3 Code's usage palette), for their bars and discs.
    readonly property var brandTint: ({ claude: "#d97757", antigravity: "#8c7bd1", opencode: "#5b9bbd",
                                        cursor: "#8b8b8b", openai: "#e8e8ea", grok: "#b8b8bc", googlegemini: "#7aa2f7",
                                        kimi: "#6d8cff", qwen: "#7f6cf0", devin: "#38bdf8", kiro: "#9046ff" })
    // The login screen's accent when the greeter is given none
    // (KUWAI_GREETER_ACCENT): kuwai's pink.
    readonly property color loginAccent: "#fc2e64"
    // Tinted surfaces (Chip, Notice): the tone at these strengths.
    readonly property real tintChip: 0.16
    readonly property real tintNotice: 0.12

    // ── Shape and space (docs/ROADMAP.md, Phase 2) ───────────────────────
    // Type scale (px). Nine steps; anything else is a bug. Weight and colour
    // carry hierarchy before size does: Primary/Secondary/Tertiary text first.
    readonly property int tCaption: 11     // badges, chip counts (no text is set below 11 px)
    readonly property int tFootnote: 12    // secondary lines, timestamps, hints
    readonly property int tSub: 13         // list detail, buttons, tips
    readonly property int tBody: 14        // rows, notification bodies (default)
    readonly property int tCallout: 15     // row titles, panel section labels
    readonly property int tHeadline: 16    // the island's clock, card titles
    readonly property int tTitle3: 19      // panel titles
    readonly property int tTitle2: 22      // big values (volume %, battery)
    readonly property int tTitle1: 26      // hero numbers; displays scale from screen size
    readonly property int tClock: 26       // the island's big clock: the hover view, the calendar, the clock in flight
    // Full-screen moments (lock, login, farewell) are read from across the
    // desk, off the panel scale on purpose.
    readonly property int tLockClock: 150      // the lock and login screens' clock
    readonly property int tLockDate: 26        // the date above it
    readonly property int tLockHeadline: 34    // the login's "Welcome back"
    readonly property int tFarewellTitle: tLockHeadline   // the farewell's title ("Shutting Down", "Sleeping"): the same size as the login's (it was 30 beside 34)
    readonly property int tLockInitial: 36     // the initial that stands in for a missing picture (login)
    readonly property int tLockName: 21        // your name under your picture (login)
    readonly property int tLockBody: 17        // a line on these screens: the unlock hint, the track playing, the farewell's line
    readonly property int tLockLine: tTitle3
    readonly property real lockClockTop: 0.11
    readonly property int lockClockGap: s1
    readonly property real lockHintAlpha: 0.85
    readonly property int lockPillW: 320
    function lockTint(accent) { return Qt.tint(Qt.rgba(1, 1, 1, 0.9), Qt.alpha(accent, 0.35)); }
    function lockClockSize(screenH) { return Math.min(tLockClock, Math.floor(screenH * 0.2 / textScale)); }
    // Glyph sizes (Symbols Nerd Font, Icon): a glyph is sized by its place.
    readonly property int glyphS: 16       // on a control or inline with a line: buttons, chevrons, nav arrows, a status mark (Icon's default)
    readonly property int glyphM: 18       // the mark that leads a row, a notice or a card, or sits in a status disc
    readonly property int glyphL: 22       // standing in for a picture: a cover with no art, a theme with no preview, a tile's "+", an empty list's mark
    readonly property int glyphXL: 28      // the mark of a large tile, an empty panel or a device card (in place of its photo)
    readonly property int glyphPlay: 32       // play/pause between the skip buttons (Now Playing; the skips take tTitle1)
    // A list row (components/ListRow): every list's rows line up on these.
    readonly property int rowInset: 10   // the row's edge to its mark, and its right edge to its state
    readonly property int rowMark: 30    // the leading mark's box (a 14 px dot sits centred in it)
    readonly property int rowGap: 12     // the mark to the text
    readonly property int rowMin: 46     // the least height of a row (Theme.sp'd: it grows with Text size)
    readonly property int r1: 8          // small controls, thumbnails
    readonly property int r2: 12         // tiles, switches
    readonly property int r3: 16         // cards, notices
    readonly property int r4: 22         // panels
    // Island panels come in four widths, not one per panel (there were
    // eleven: 400, 420, 440, 560, 620, 640, 720, 760, 762, 780, 980). A panel
    // you switch to at the same size doesn't re-morph the island sideways.
    readonly property int panelS: 460    // a list or a card: Agents, Usage, T3, Notifications, Bluetooth, Now Playing
    readonly property int panelM: 640    // a list with detail: Launcher, System, Power, Cleanup
    readonly property int panelL: 800    // two columns: Settings, Updates, Shortcuts
    readonly property int cardW: panelS
    readonly property int cardWNarrow: panelS - 40
    readonly property int panelXL: 980   // a gallery: Themes
    readonly property int panelMaxH: 600 // the most height the island gives a panel (its window is 640; bin/kuwai-rehearse's ISLAND)
    readonly property int s1: 4
    readonly property int s2: 8
    readonly property int s3: 12
    readonly property int s4: 16
    readonly property int s5: 24

    // ── Text ─────────────────────────────────────────────────────────────
    // Over blur, flat grey washes out: keep secondary/tertiary brighter than
    // on a solid surface (vibrancy), and lean on weight for hierarchy.
    readonly property color textPrimary: Qt.rgba(1, 1, 1, 0.96)
    readonly property color textSecondary: Qt.rgba(1, 1, 1, contrast ? 0.88 : 0.72)
    readonly property color textTertiary: Qt.rgba(1, 1, 1, contrast ? 0.74 : 0.56)
    readonly property color textDim: Qt.rgba(1, 1, 1, contrast ? 0.76 : 0.55)

    // Apple's dark-mode system colours: tuned to read on dark material.
    readonly property color red: "#ff453a"
    readonly property color orange: "#ff9f0a"
    readonly property color yellow: "#ffd60a"
    readonly property color green: "#30d158"
    readonly property color blue: "#0a84ff"
    readonly property color positive: green
    readonly property color caution: orange
    readonly property color critical: red
    // Fixed state colours (Apple's dark palette), named once so no file types the hex.
    readonly property color focus: "#bf5af2"     // Focus / Do Not Disturb (purple)
    readonly property color purple: focus       // Apple's purple: the screen-shared/recorded dot
    readonly property color indigo: "#5e5ce6"    // secondary actions, sliders
    readonly property color gray: "#8e8e93"      // Apple's system grey: neutral tiles (Settings → Keyboard)
    readonly property color cyan: "#64d2ff"      // info, links on dark
    readonly property color pink: "#ff375f"      // Apple's pink: music (a player's sound source)
    readonly property color brown: "#ac8e68"     // Apple's brown: one more categorical hue
    readonly property color mint: "#66d4cf"      // Apple's mint: one more categorical hue
    // Red as words (a critical label): Apple's accessible red, lighter than
    // red so it reads as text on glass.
    readonly property color redText: "#ff6961"
    readonly property color inkOnLight: glassBlack   // text and glyphs on a light fill: a selected chip, today, a white badge or button

    // The theme's own colour, the way HyDE's colour mode says (Themes panel →
    // Colours, or HyDE's wallbash toggle; enableWallDcol in its staterc):
    //   theme  the theme's palette: its theme.dcol when it ships one, else its
    //          kitty.theme (blue slot = accent)
    //   auto · dark · light   the wallpaper's wallbash palette (wall.dcol)
    // The island's accent, glows, pills and status icons follow it live. The
    // island body itself stays near-black in every mode, like the hardware
    // island it's modelled on; light themes tint it, never whiten it.
    property color accent: blue
    // One commit per recolour; only the always-visible fills blend (accentLive).
    property color accentLive: accent
    Behavior on accentLive { ColorAnimation { duration: root.artMs; easing.type: Easing.OutCubic } }
    property color accentSoft: Qt.rgba(0.04, 0.52, 1, 0.5)
    // Text and glyphs that sit *on* the accent: dark on light accents, white on dark.
    function luminance(c) {
        function linear(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b);
    }
    function contrast(a, b) {
        const la = luminance(Qt.color(a)), lb = luminance(Qt.color(b));
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }
    function inkFor(surfaces, target) {
        const list = Array.isArray(surfaces) && surfaces.length ? surfaces : [themeBg];
        const minW = Math.min.apply(null, list.map(s => contrast("#ffffff", s)));
        const minB = Math.min.apply(null, list.map(s => contrast("#000000", s)));
        return minB >= minW ? "#000000" : "#ffffff";
    }
    function wash(step) {
        const table = [0.03, 0.06, 0.10, 0.14, 0.20, 0.28];
        const i = Math.max(0, Math.min(table.length - 1, Math.round(step)));
        return Qt.rgba(1, 1, 1, table[i]);
    }
    function edge(step) {
        const table = [0.06, 0.10, 0.15, 0.22, 0.32, 0.45];
        const i = Math.max(0, Math.min(table.length - 1, Math.round(step)));
        return Qt.rgba(1, 1, 1, table[i]);
    }
    function materialSpec(level) {
        if (level === "thin") return { tint: Qt.rgba(0.067, 0.067, 0.078, contrast ? 0.88 : 0.44), rim: edge(0), sheen: 0.14, darkRing: 0.45 };
        if (level === "thick") return { tint: glassTintThick, rim: edge(1), sheen: 0.18, darkRing: 0.58 };
        if (level === "elevated") return { tint: glassTintElevated, rim: edge(1), sheen: 0.20, darkRing: 0.62 };
        if (level === "island") return { tint: glassIsland, rim: edge(1), sheen: 0.10, darkRing: 0.70 };
        if (level === "solid") return { tint: glassSolid, rim: edge(1), sheen: 0.0, darkRing: 0.65 };
        return { tint: glassTint, rim: edge(0), sheen: 0.20, darkRing: 0.55 };
    }
    function contrastInk(c) {
        const y = luminance(c);
        return (y + 0.05) / 0.05 >= 1.05 / (y + 0.05) ? "#000000" : "#ffffff";
    }
    readonly property color onAccent: contrastInk(accent)
    readonly property color onDanger: contrastInk(red)
    property color themeBg: "#16161d"         // the palette's own background
    property color themeFg: "#ffffff"
    property var palette: []                   // a few swatches, for pickers
    property int colorMode: 0                  // 0 theme · 1 auto · 2 dark · 3 light
    property string themeName: ""
    readonly property string hydeThemes: Quickshell.env("HOME") + "/.config/hyde/themes/"
    readonly property string kuwaiLookPath: Paths.stateHome + "/kuwai/look/current/palette.json"
    property real wallTopLuma: 0.1
    property color wallInk: "#ffffff"

    // The theme's colour, made vivid enough to read as an accent: its hue is
    // kept, saturation and lightness pulled into the band of the voxtype HUD's
    // colours (#66C7FF, #86E0B4, #FF7A98: S ≥ 0.6, L 0.62–0.74). A washed-out
    // wallpaper pink becomes a clear pink; near-grey themes (1-Bit) stay grey.
    function vivid(c) {
        c = Qt.color(c);
        const h = c.hslHue, s = c.hslSaturation, l = c.hslLightness;
        if (h < 0 || s < 0.12) return Qt.hsla(0, 0, Math.max(0.62, Math.min(0.8, l)), 1);
        return Qt.hsla(h, Math.max(0.62, s), Math.max(0.62, Math.min(0.74, l)), 1);
    }
    function parseDcol(text) {
        const v = {};
        for (const l of text.split("\n")) {
            const m = l.match(/^dcol_([a-z0-9]+)="([0-9A-Fa-f]{6})"$/);
            if (m) v[m[1]] = "#" + m[2];
        }
        return v;
    }
    function fromDcol(v) {
        if (!v.pry1 && !v["1xa7"]) return null;
        const c = { palette: ["pry1", "pry2", "1xa7", "2xa7", "3xa7", "4xa7"].filter(k => v[k]).map(k => v[k]) };
        if (v["1xa7"]) c.accent = vivid(v["1xa7"]);
        if (v["1xa5"]) c.accentSoft = Qt.color(v["1xa5"]);
        if (v.pry1) c.themeBg = Qt.color(v.pry1);
        if (v.txt1) c.themeFg = Qt.color(v.txt1);
        return c;
    }
    function fromKitty(text) {
        const v = {};
        for (const l of text.split("\n")) {
            const p = l.trim().split(/\s+/);
            if (p.length >= 2 && /^#[0-9A-Fa-f]{6}$/.test(p[1])) v[p[0]] = p[1];
        }
        if (!v.color4) return null;
        const c4 = Qt.color(v.color4);
        const c = { accent: vivid(v.color4), accentSoft: Qt.rgba(c4.r, c4.g, c4.b, 0.5),
                    palette: ["background", "color1", "color3", "color2", "color6", "color4", "color5"].filter(k => v[k]).map(k => v[k]) };
        if (v.background) c.themeBg = Qt.color(v.background);
        if (v.foreground) c.themeFg = Qt.color(v.foreground);
        return c;
    }
    function fromKuwaiLook(text) {
        try {
            const d = JSON.parse(text);
            if (!d || d.schema !== 1 || !d.role || !d.role.accent) return null;
            const m = d.mode || "dark";
            const c = { accent: Qt.color(d.role.accent), colorMode: m === "theme" ? 0 : m === "auto" ? 1 : m === "light" ? 3 : 2 };
            if (d.role.accentSoft) c.accentSoft = Qt.color(d.role.accentSoft);
            if (d.role.bg) c.themeBg = Qt.color(d.role.bg);
            if (d.role.fg) c.themeFg = Qt.color(d.role.fg);
            if (Array.isArray(d.swatches) && d.swatches.length > 0) c.palette = d.swatches;
            if (d.source && d.source.name) c.themeName = String(d.source.name);
            if (d.wall && typeof d.wall.topLuma === "number") c.wallTopLuma = d.wall.topLuma;
            if (d.wall && d.wall.ink) c.wallInk = Qt.color(d.wall.ink);
            return c;
        } catch (e) {
            return null;
        }
    }
    function reloadLook() {
        kuwaiPalette.reload();
    }
    function colours() {
        const look = kuwaiPalette.loaded ? fromKuwaiLook(kuwaiPalette.text()) : null;
        if (look) return look;
        if (colorMode === 0 && themeName) {
            const dcol = themeDcol.loaded ? fromDcol(parseDcol(themeDcol.text())) : null;
            if (dcol) return dcol;
            const kitty = themeKitty.loaded ? fromKitty(themeKitty.text()) : null;
            if (kitty) return kitty;
        }
        return wallDcol.loaded ? fromDcol(parseDcol(wallDcol.text())) : null;
    }
    function commit(c) {
        if (!c) return 0;
        let n = 0;
        for (const k of ["accent", "accentSoft", "themeBg", "themeFg", "wallInk"])
            if (c[k] !== undefined && !Qt.colorEqual(root[k], c[k])) { root[k] = c[k]; n++; }
        for (const k of ["themeName", "colorMode", "wallTopLuma"])
            if (c[k] !== undefined && root[k] !== c[k]) { root[k] = c[k]; n++; }
        if (c.palette && JSON.stringify(c.palette) !== JSON.stringify(root.palette)) { root.palette = c.palette; n++; }
        return n;
    }
    property bool coloured: false
    property bool recolorHeld: false
    property bool recolorDirty: false
    function recolor() {
        if (!root.coloured) root.commit(root.colours());
        if (root.recolorHeld) { root.recolorDirty = true; return; }
        root.recolorSettle.restart();
    }
    function holdRecolor(on) {
        root.recolorHeld = !!on;
        if (root.recolorHeld) {
            if (root.recolorSettle.running) { root.recolorSettle.stop(); root.recolorDirty = true; }
            return;
        }
        if (root.recolorDirty) {
            root.recolorDirty = false;
            root.coloured = true;
            root.commit(root.colours());
        }
    }
    function flushRecolor() {
        root.recolorHeld = false;
        if (!root.recolorDirty && !root.recolorSettle.running) return 0;
        root.recolorDirty = false;
        root.recolorSettle.stop();
        root.coloured = true;
        return root.commit(root.colours());
    }
    property Timer recolorSettle: Timer { interval: root.recolorMs; onTriggered: { root.coloured = true; root.commit(root.colours()); } }
    FileView {
        id: kuwaiPalette
        property bool loaded: false
        path: root.kuwaiLookPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { loaded = true; root.recolor(); }
        onLoadFailed: { loaded = false; root.recolor(); }
    }
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/hyde/staterc"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const t = text();
            const m = t.match(/^enableWallDcol="?(\d)"?/m);
            const n = t.match(/^HYDE_THEME="?([^"\n]+)"?/m);
            root.colorMode = m ? parseInt(m[1]) : 0;
            root.themeName = n ? n[1] : "";
            root.recolor();
        }
    }
    FileView {
        id: themeDcol
        property bool loaded: false
        path: root.themeName ? root.hydeThemes + root.themeName + "/theme.dcol" : ""
        printErrors: false
        onPathChanged: loaded = false
        onLoaded: { loaded = true; root.recolor(); }
        onLoadFailed: { loaded = false; root.recolor(); }
    }
    FileView {
        id: themeKitty
        property bool loaded: false
        path: root.themeName ? root.hydeThemes + root.themeName + "/kitty.theme" : ""
        printErrors: false
        onPathChanged: loaded = false
        onLoaded: { loaded = true; root.recolor(); }
        onLoadFailed: { loaded = false; root.recolor(); }
    }
    FileView {
        id: wallDcol
        property bool loaded: false
        path: Quickshell.env("HOME") + "/.cache/hyde/wall.dcol"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { loaded = true; root.recolor(); }
    }

    // ── Type ─────────────────────────────────────────────────────────────
    // The UI face is resolved once, at start, from what is installed
    // (Qt.fontFamilies), in this order:
    //   sf      Apple's SF Pro (Text below 20 px, Display from 20, Rounded for
    //           numerals) with Apple's own tracking. Used when it's installed;
    //           kuwai doesn't ship it (Apple's licence limits it to Apple
    //           platforms), so it is an upgrade, never a requirement.
    //   inter   Inter (OFL, Arch's `inter-font` in [extra]): the default
    //           anyone can install. Inter 4 has optical sizes too: the static
    //           "Inter" + "Inter Display" pair, or the variable font's opsz
    //           axis (14–32). Its spacing is built into each optical size, so
    //           no tracking table; no rounded cut, so numerals take its open
    //           digits (ss01) instead.
    //   system  whatever fontconfig calls sans-serif: no tracking, no features.
    // KUWAI_FONT=sf|inter|system picks one of those that is installed.
    //   fontGlyph    Symbols Nerd Font, never mixed into text runs
    // SF Compact (watchOS) and New York (serif) don't belong in a desktop UI.
    readonly property var installedFonts: Qt.fontFamilies()
    // An output can report 0 (or nothing) for its size for a moment while it
    // is added, moved or rescaled. Windows size from this, never straight
    // from screen.width/height: a reading under minScreen isn't trusted and
    // `fallback` stands in, so nothing computes a zero or negative size (the
    // tooltip that collapsed into a one-letter column).
    readonly property int minScreen: 320
    function screenSize(screen, axis, fallback) {
        const v = screen ? screen[axis] : NaN;
        return Number.isFinite(v) && v >= minScreen ? v : fallback;
    }
    function hasFont(name) { return installedFonts.indexOf(name) >= 0; }
    readonly property bool hasSf: hasFont("SF Pro Text") && hasFont("SF Pro Display")
    readonly property string interFamily: hasFont("Inter") && hasFont("Inter Display") ? "Inter"
                                        : hasFont("Inter Variable") ? "Inter Variable"
                                        : hasFont("Inter") ? "Inter" : ""
    readonly property string fontKind: {
        const want = (Quickshell.env("KUWAI_FONT") || "").toLowerCase();
        if (want === "system") return "system";
        if (want === "inter" && interFamily) return "inter";
        if (want === "sf" && hasSf) return "sf";
        return hasSf ? "sf" : interFamily ? "inter" : "system";
    }
    readonly property string systemFamily: Qt.application.font.family || "sans-serif"
    readonly property string fontText: fontKind === "sf" ? "SF Pro Text" : fontKind === "inter" ? interFamily : systemFamily
    readonly property string fontDisplay: fontKind === "sf" ? "SF Pro Display"
                                        : fontKind === "inter" && interFamily === "Inter" && hasFont("Inter Display") ? "Inter Display"
                                        : fontText
    // SF Pro Rounded only beside SF Pro; elsewhere numerals are the text face.
    readonly property bool roundedFace: fontKind === "sf" && hasFont("SF Pro Rounded")
    readonly property string fontRounded: roundedFace ? "SF Pro Rounded" : fontText
    readonly property string fontUi: fontText          // older name, same face
    readonly property string fontGlyph: "Symbols Nerd Font"
    readonly property string fontMono: hasFont("SF Mono") ? "SF Mono" : hasFont("Geist Mono") ? "Geist Mono" : hasFont("GeistMono Nerd Font") ? "GeistMono Nerd Font" : "monospace"   // code and raw text
    // A variable Inter without its static Display cut: optical size goes
    // through the opsz axis (Label sets it).
    readonly property bool fontOpszAxis: fontKind === "inter" && fontDisplay === fontText

    // Apple's SF weights (Inter's nearest instances are 400/500/600/700)
    readonly property int wRegular: 400
    readonly property int wMedium: 510
    readonly property int wSemibold: 590
    readonly property int wBold: 700

    // Tracking (px) by size, from SF Pro's own `trak` tables (track 0,
    // 1/2048 em per point size), which macOS applies and Qt doesn't. Only for
    // SF Pro: they were measured for it, and Inter's spacing is per optical size.
    readonly property var trakSizes:   [6, 9, 10, 11, 12, 13, 14, 15, 16, 17, 20, 22, 24, 28, 32, 36, 50, 64, 80]
    readonly property var trakPro:     [82, 38, 24, 12, 0, -12, -22, -32, -40, -52, -46, -24, 6, 28, 26, 21, 14, 7, 0]
    readonly property var trakRounded: [174, 130, 116, 104, 92, 80, 70, 60, 52, 45, 37, 32, 29, 26, 24, 22, 14, 6, 0]
    function tracking(px, rounded) {
        if (fontKind !== "sf") return 0;
        const xs = trakSizes, ys = rounded && roundedFace ? trakRounded : trakPro;
        let v = ys[ys.length - 1];
        if (px <= xs[0]) v = ys[0];
        else for (let k = 1; k < xs.length; k++) {
            if (px <= xs[k]) {
                const t = (px - xs[k - 1]) / (xs[k] - xs[k - 1]);
                v = ys[k - 1] + (ys[k] - ys[k - 1]) * t;
                break;
            }
        }
        return v / 2048 * px;
    }
    // Three optical sizes, not one per pixel size: every distinct value is its
    // own font face with its own glyph cache (and its own mapping of the
    // variable font). SF Pro: Text 17 up to 19 px, a middle cut, Display from
    // 25 px. Inter (opsz 14–32): text 14, the same middle, display 32.
    function opszFor(px) {
        if (fontKind === "inter") return px < 20 ? 14 : px < 25 ? 22 : 32;
        return px < 20 ? 17 : px < 25 ? 22 : 28;
    }
    readonly property var noAxes: ({})
    // What Label sets on font.variableAxes: the optical size where only the
    // axis can give it (a variable Inter), nothing otherwise.
    function axesFor(px) { return fontOpszAxis ? { "opsz": opszFor(px) } : noAxes; }
    // The same with a weight, for text that sets its own (TextMorph, RollingNumber).
    function axesWeight(px, w) { return fontOpszAxis ? { "opsz": opszFor(px), "wght": w } : { "wght": w }; }
    // Numerals' OpenType features. Rounded: SF Pro Rounded is its own face;
    // Inter's nearest is its open digits (ss01: 6, 9, 4 open). Tabular for
    // anything that changes in place (clocks, levels, counts).
    readonly property var featTabular: ({ "tnum": 1 })
    readonly property var featOpen: ({ "ss01": 1 })
    readonly property var featOpenTabular: ({ "ss01": 1, "tnum": 1 })
    readonly property var noFeatures: ({})
    function numeralFeatures(rounded, tabular) {
        if (rounded && fontKind === "inter") return tabular ? featOpenTabular : featOpen;
        return tabular ? featTabular : noFeatures;
    }

    // ── Motion ───────────────────────────────────────────────────────────
    // Curves (Emil Kowalski's strong curves; Qt's built-ins are too weak):
    //   easeOut     entering, exiting, anything the user is waiting on
    //   easeInOut   something moving or morphing on screen
    //   easeDrawer  iOS sheet curve, for panels arriving from an edge
    // Never ease-in on UI: it delays the moment the user is watching.
    // UI stays under 300ms; feedback for keypresses (the HUD) near 150.
    readonly property var easeOut: [0.23, 1, 0.32, 1, 1, 1]
    readonly property var easeInOut: [0.77, 0, 0.175, 1, 1, 1]
    readonly property var easeDrawer: [0.32, 0.72, 0, 1, 1, 1]
    readonly property var easeSine: [0.37, 0, 0.63, 1, 1, 1]
    readonly property var easeLinear: [0, 0, 1, 1, 1, 1]
    readonly property var easeIn: [0.55, 0.085, 0.68, 0.53, 1, 1]
    function innerRadius(outer, inset) { return Math.max(4, Math.round(outer - inset)); }
    readonly property int durInstant: 80
    readonly property int durExit: 100
    readonly property int durFast: 140
    readonly property int durBase: 200
    readonly property int durSettle: 260
    readonly property int durSlow: 400
    readonly property int durGentle: 700
    readonly property int pressMs: durFast          // press feedback (scale 0.97)
    readonly property int enterMs: durBase          // small surfaces arriving, rows growing
    readonly property int exitMs: durFast           // leaving: quicker than arriving
    readonly property int glideMs: durFast          // values chasing a target (level fill, meters)
    readonly property int reflowMs: durBase         // neighbours closing a gap
    readonly property int colorMs: durFast
    readonly property int hoverMs: durInstant           // hover tints: answer the pointer at once
    readonly property int recolorMs: durSettle
    readonly property int artMs: durSlow            // a colour following its new source: album art after a new track, the accent after a theme change
    readonly property int spinMs: 750           // one turn of a spinner: brisk (a faster turn reads as faster work; every spinner uses it)
    readonly property int stepMs: 600           // one step of a working ring (glides, then rests ~2.4 s)
    // The one beat every working ring on the notch steps to: T3's and an
    // update's moved on their own timers, so two rings side by side ticked
    // out of phase (a queue, not one rhythm). One wake every 3 s, only while a ring shows.
    readonly property int stepEvery: 3000
    property int step: 0
    property int stepUsers: 0
    property Timer stepClock: Timer { interval: root.stepEvery; repeat: true; running: root.stepUsers > 0 && !root.reduceMotion; onTriggered: root.step++ }
    readonly property int quickMs: durFast          // a quick fade in place: tooltips, hints, a caret
    readonly property int microMs: durFast          // a small state change in place: an icon's fill, a fade, a press
    readonly property int pulseMs: 520          // half a quick pulse (InOutSine there and back)
    readonly property int breatheMs: durGentle        // half a slow breath (a live mic, a waiting dot)
    // Hover timing, one set for the whole shell: things open after
    // Settings.hoverDelay (your setting), stay hoverLeaveMs after the pointer
    // leaves (crossing a gap doesn't close them), and tooltips wait tipMs
    // (slower than panels on purpose: no flashing as you cross the island).
    readonly property int hoverLeaveMs: 300
    readonly property int tipMs: 450
    // One loading sweep everywhere (Shimmer, the reasoning label, the notch's edge light): brisk, not drifting.
    readonly property int shimmerMs: 1300
    readonly property int hudInMs: durBase          // the HUD answers a keypress: fast, 6px, no scale bounce
    readonly property int hudOutMs: durFast
    // Cards that grow out of the island (DeviceCard, AlarmCard).
    readonly property int cardInMs: 300         // the mark coming up
    readonly property int cardRiseMs: 260       // each line rising 4 px into place
    readonly property int ringDrawMs: 480       // a ring drawing itself closed
    readonly property int swingMs: durGentle          // a bell's damped swing, all of it
    readonly property int breathOutMs: 1100
    readonly property int wallRevealMs: 1100
    readonly property int wallCutMs: 1400
    readonly property int wallFadeMs: 120
    readonly property int handoffMs: 30          // one swap's new content waits this long for the old to start leaving
    readonly property int settleMs: durSettle          // settling into a new place or size, not arriving: a surface resizing to fit, a pulled one let go, a farewell undone
    readonly property int kickMs: durInstant             // the quick first half of a there-and-back: a rubber band's stretch, a typed dot's pop, a bump, a miss
    readonly property int bumpBackMs: 300        // an update in place settling back from its 1.02 bump (NotifCard)
    readonly property int flashFadeMs: 900       // a one-time flash fading out: a critical toast's arrival ring, a wrong password's red ring
    readonly property int morphMs: 560           // one character morphing (TextMorph's default)
    readonly property int morphSmallMs: 320      // a number morphing inside a small ring (StatRing)
    readonly property int holdMs: 800            // a deliberate hold (the login's power buttons): slow, you're deciding
    readonly property int holdShortMs: 350       // a status icon's press-and-hold (QuickIcon)
    readonly property int caretBlinkMs: 530      // a resting caret's blink, the platform rate
    readonly property int peakFollowMs: 60       // a live level following its peaks: just enough to smooth the steps
    readonly property int peakFallMs: 1600       // a meter's peak-hold line falling back
    readonly property int waveSettleMs: 380      // the now-playing bars settling to their pause shape
    readonly property int menuInMs: durFast
    readonly property int menuOutMs: durExit
    readonly property int ambientFadeMs: 600     // something behind everything fading by itself (a live wallpaper's video)
    // A device card's own beats (DeviceCard; it enters like AlarmCard).
    readonly property int cardPingMs: 450        // the link closing sends one ping out
    readonly property int cardSettleMs: 320      // what lands as the link closes (the badge, the battery) settling in
    readonly property int cardLevelMs: 600       // a sound device's level filling in once it's connected
    readonly property int cardGoWaitMs: 260      // a device leaving: the ring waits this long…
    readonly property int cardUnlinkMs: 420      // …then undoes itself
    // Lock, login and farewell (full-screen moments: slower, they are rare).
    readonly property int unlockLeadMs: 60
    readonly property int unlockMs: 320          // the lock lifting away
    readonly property int unlockReleaseMs: (reduceMotion ? 0 : unlockLeadMs) + unlockMs + 20
    readonly property int shackleWaitMs: 380     // the padlock waits for the island to land before it clicks shut
    readonly property int shackleShutMs: 260     // the shackle clicking shut
    readonly property int shackleOpenWaitMs: 0   // the shackle opens with the unlock, not before it
    readonly property int shackleOpenMs: 220     // the shackle springing open
    readonly property int idleDimMs: 14000       // the screen dimming before it sleeps (any movement lifts it)
    readonly property int greetStepMs: 420       // one part of the login's intro rising in
    readonly property int greetWallMs: 1400      // the login's wallpaper coming up out of black
    readonly property int greetClockMs: 560      // the login's clock arriving
    readonly property int greetOutMs: 380        // the login stepping aside as you log in
    readonly property int loginRevealMs: 720     // your picture opening into your desktop
    readonly property int farewellMarkMs: 900    // the farewell's mark doing its one motion
    readonly property int farewellHoldMs: 250    // a beat on the finished mark before black
    readonly property int farewellOutMs: 420     // into black
    readonly property int chargeFillMs: 900      // plugged in on the lock screen: the battery fills from empty to its level…
    readonly property int chargeHoldMs: 500      // …holds there, then shows the live value
    readonly property int chargeRingDelayMs: 120 // its two rings ping out this long after the fill starts…
    readonly property int chargeRingGapMs: 220   // …this far apart
    // Screensaver: ambient, minutes not milliseconds.
    readonly property int saverZoomMs: 40000     // the still's slow zoom, each way
    readonly property int saverMoveMs: 6000      // the clock gliding to its new place each minute
    readonly property int duskMeteorWaitMs: 14000  // Dusk: quiet sky before a shooting star…
    readonly property int duskMeteorInMs: 180      // …it flashes on…
    readonly property int duskMeteorMs: 900        // …crosses (fading over the second half)…
    readonly property int duskMeteorRestMs: 9000   // …and the sky rests again
    readonly property int duskLightWaitMs: 2000    // Dusk: the first town window lights after this (the rest follow)
    readonly property int duskLightOnMs: 600       // a window lighting up
    readonly property int duskLightStayMs: 12000   // the least a window stays lit
    readonly property int duskLightOffMs: 900      // a window going dark
    readonly property int duskStarSize: 5          // Dusk: a star's size (px; ±4)
    // Dusk's palette (an original evening): the sky top to horizon, then the
    // scene from far to near.
    readonly property var duskPalette: ({
        sky: ["#0b1030", "#202862", "#4a3a7a", "#a35a82", "#f0937a", "#ffc98c"],
        star: "#fff6e8", halo: "#fff0d8", moonTop: "#fffaf0", moonBottom: "#f6dcc0",
        clouds: ["#e9b8c8", "#d9a0b8", "#c8b8e8"], meteor: "#fffbe8",
        farHills: "#6a4a7e", midHills: "#3d2c5a", town: "#2a1f42", ground: "#160f26", window: "#ffd38a"
    })
    // Borealis (the second drawn screensaver, modules/screensaver/BorealisScene): curtains of
    // light in the theme's own accent over a near-black sky and a ridge. The sky and ridge are
    // fixed; the curtains take Theme.accent and a hue either side of it.
    readonly property int borealisSwayMs: 26000    // a curtain drifting one way (it eases back the same time)
    readonly property int borealisPulseMs: 15000   // a curtain's brightness breathing, each way
    readonly property int borealisRays: 110        // rays per curtain (a curtain is drawn once, then only moved)
    readonly property int borealisStarSize: 4      // a star's size (px; ±3)
    readonly property real borealisFallbackHue: 0.45   // a grey accent has no hue: a green-teal one
    readonly property real borealisMinSat: 0.62    // …and a pale accent is made vivid enough to read as light
    readonly property var borealisPalette: ({
        sky: ["#02050a", "#05101a", "#0a1f2a"], star: "#e8f4ff",
        farRidge: "#07141c", ridge: "#030a0f", rim: "#10303c"
    })
    // One undo window for everything that can be taken back: "Cleared N ·
    // Undo" after clearing notifications, "Deleted · ⌃Z to undo" after
    // deleting a copy. Long enough to notice and reach (Material's snackbar:
    // 4–10 s), short enough that it is soon final.
    readonly property int undoMs: 6000
    readonly property int panelPollMs: 5000     // live numbers that need a process, only while their panel is open

    // Reduced motion: fewer and gentler: fades and colour stay, travel,
    // scale and stagger go. On when you switch it on (Controls → Reduce
    // Motion, remembered in ~/.local/state/kuwai/prefs.json), when
    // KUWAI_REDUCE_MOTION=1, or when Hyprland's own animations are off.
    readonly property bool inGreeter: (Quickshell.env("KUWAI_GREETER_USER") || "") !== ""
    readonly property bool reduceMotion: prefs.reduceMotion || envReduce || (hyprStill && !inGreeter)
    readonly property bool userReduce: prefs.reduceMotion
    readonly property bool envReduce: Quickshell.env("KUWAI_REDUCE_MOTION") === "1"
    property bool hyprStill: false
    function setReduceMotion(on) { prefs.reduceMotion = on; }
    Process {
        id: stillProbe
        running: true
        command: ["hyprctl", "getoption", "animations:enabled", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.hyprStill = JSON.parse(text).int === 0; } catch (e) {}
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded" && !stillProbe.running) stillProbe.running = true; }
    }
    FileView {
        path: Paths.stateHome + "/kuwai/prefs.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter(); }
        JsonAdapter {
            id: prefs
            property bool reduceMotion: false
        }
    }

    // ── Springs: Fluid Functionalism's three tiers (refs/mickadesign_…) ──
    // The bigger the thing that moves, the slower the tier; never hand-write
    // a duration. Motion's `duration` means "settled to 0.1%", so these are
    // solved for that: ω from ζ·ω·d ≈ 6.9, k = ω², c = 2ζω (mass 1).
    //   fast      0.08s, no bounce: hover highlights, fades, focus rings
    //   moderate  0.16s, critically damped: tabs, dropdowns, panels that must land exactly
    //   slow      0.24s, bounce 0.12: dialogs, drawers, large surfaces, morphs
    // Exits are plain tweens one tier quicker, never the enter spring reversed.
    readonly property var springFast: ({ stiffness: 13300, damping: 231, exitMs: 60 })
    readonly property var springModerate: ({ stiffness: 3329, damping: 115, exitMs: 120 })
    readonly property var springSlow: ({ stiffness: 1069, damping: 57.5, exitMs: 160 })
    // Surfaces that grow out of the island (panels, the clipboard shelf,
    // Quick Look, Mission Control): one motion everywhere, critically damped
    // (no wobble), ~0.33 s to grow, a touch firmer to fold back. From the
    // keyboard the same curve, a little quicker (~0.24 s), never a snap.
    // 2026-11-17: growing has a touch of give (ζ 0.8, ~1.5 % past the target,
    // then settles), the way the Dynamic Island lands (Apple; Clove: response
    // 0.42 / damping 0.78 to grow, critically damped to shrink; Emil: springs
    // for "alive" elements, bounce ≤ 0.3). Folding back, and anything the
    // keyboard opened, stays critically damped: it's getting out of the way.
    readonly property var surfaceIn: ({ stiffness: 300, damping: 27.7 })
    readonly property var surfaceOut: ({ stiffness: 560, damping: 47.3 })
    readonly property var surfaceKeyIn: ({ stiffness: 560, damping: 47.3 })
    readonly property var surfaceKeyOut: ({ stiffness: 900, damping: 60 })

    // ── Toast stack: Sonner's numbers (emilkowalski/sonner, refs/) ───────
    readonly property int toastWidth: 368        // Sonner 356; ours carries an icon
    readonly property int stackGap: 14           // GAP
    readonly property int stackVisible: 3        // VISIBLE_TOASTS_AMOUNT
    readonly property real stackScaleStep: 0.05  // each toast behind is 5% smaller
    readonly property int stackMs: durSlow           // transform/opacity/height transition
    readonly property var easeCss: [0.25, 0.1, 0.25, 1, 1, 1]     // CSS `ease`
    readonly property var easeOutCss: [0, 0, 0.58, 1, 1, 1]       // CSS `ease-out`
    readonly property int swipeThreshold: 45     // px, or…
    readonly property real swipeVelocity: 0.11   // px/ms averaged over the gesture (Sonner's; the lock screen's own check)
    readonly property real swipeFlick: 0.5       // px/ms at release (components/Fling): a flick dismisses on its own
    readonly property int swipeOutMs: durBase
    readonly property int unmountMs: durBase         // TIME_BEFORE_UNMOUNT
    // Movement the wrong way is damped, not blocked, so it feels elastic.
    function swipeDamp(d) {
        const damped = d / (1.5 + Math.abs(d) / 20);
        return Math.abs(damped) < Math.abs(d) ? damped : d;
    }

    // ── Layout ───────────────────────────────────────────────────────────
    readonly property int barGap: 6             // distance below Waybar's exclusive zone
}
