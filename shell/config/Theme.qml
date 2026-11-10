// Design tokens for every surface in the rice. The look is the glass HUD's:
// Hyprland blurs what is behind a layer, a dark translucent tint sits on top,
// text is Inter (variable, optical size + exact weight) with SF Pro Display
// for display sizes, glyphs come from Symbols Nerd Font. Motion is critically
// damped (no bounce): surfaces arrive fast and settle, and leave the way they
// came, a little quicker. See docs/DESIGN.md.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // Accessibility (Settings → Accessibility): more contrast, less glass.
    readonly property bool contrast: Settings.highContrast
    readonly property real textScale: Math.max(1, Math.min(1.3, Settings.textScale || 1))
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
    readonly property color platter: Qt.rgba(1, 1, 1, 0.15)
    readonly property color platterDim: Qt.rgba(1, 1, 1, 0.08)
    readonly property color track: Qt.rgba(1, 1, 1, 0.18)
    readonly property color fill: Qt.rgba(1, 1, 1, 0.96)
    readonly property color fillDim: Qt.rgba(1, 1, 1, 0.32)
    readonly property color pill: Qt.rgba(1, 1, 1, 0.12)
    readonly property color pillHover: Qt.rgba(1, 1, 1, 0.22)
    // Grouped content inside a panel (components/ui/Card): a whisper of a
    // surface and a hairline, so cards separate without boxes everywhere.
    readonly property color card: Qt.rgba(1, 1, 1, 0.05)
    readonly property color cardEdge: Qt.rgba(1, 1, 1, contrast ? 0.22 : 0.05)
    // A round grey button on black (iOS's stop ✕): rest and hover.
    readonly property color knob: "#3a3a3c"
    readonly property color knobHover: "#4a4a4e"
    readonly property color chip: Qt.rgba(0.11, 0.11, 0.12, 1)   // an opaque disc on black (stacked logos)
    readonly property int statRingSize: 40   // the hover view's rings (machine and agents)
    // Agents' own colours (T3 Code's usage palette), for their bars and discs.
    readonly property var brandTint: ({ claude: "#d97757", antigravity: "#8c7bd1", opencode: "#5b9bbd",
                                        cursor: "#8b8b8b", openai: "#e8e8ea", grok: "#b8b8bc", googlegemini: "#7aa2f7",
                                        kimi: "#6d8cff", qwen: "#7f6cf0" })
    // Tinted surfaces (Chip, Notice): the tone at these strengths.
    readonly property real tintChip: 0.16
    readonly property real tintNotice: 0.12

    // ── Shape and space (docs/ROADMAP.md, Phase 2) ───────────────────────
    // Type scale (px). Nine steps; anything else is a bug. Weight and colour
    // carry hierarchy before size does: Primary/Secondary/Tertiary text first.
    readonly property int tCaption: 10     // badges, chip counts, meta under meta
    readonly property int tFootnote: 11    // secondary lines, timestamps, hints
    readonly property int tSub: 12         // list detail, buttons, tips
    readonly property int tBody: 13        // rows, notification bodies (default)
    readonly property int tCallout: 14     // row titles, panel section labels
    readonly property int tHeadline: 15    // the island's clock, card titles
    readonly property int tTitle3: 18      // panel titles
    readonly property int tTitle2: 20      // big values (volume %, battery)
    readonly property int tTitle1: 24      // hero numbers; displays scale from screen size
    readonly property int r1: 8          // small controls, thumbnails
    readonly property int r2: 12         // tiles, switches
    readonly property int r3: 16         // cards, notices
    readonly property int r4: 22         // panels
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
    readonly property color textTertiary: Qt.rgba(1, 1, 1, contrast ? 0.74 : 0.50)
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
    readonly property color indigo: "#5e5ce6"    // secondary actions, sliders
    readonly property color cyan: "#64d2ff"      // info, links on dark

    // The theme's own colour, the way HyDE's colour mode says (Themes panel →
    // Colours, or HyDE's wallbash toggle; enableWallDcol in its staterc):
    //   theme  the theme's palette: its theme.dcol when it ships one, else its
    //          kitty.theme (blue slot = accent)
    //   auto · dark · light   the wallpaper's wallbash palette (wall.dcol)
    // The island's accent, glows, pills and status icons follow it live. The
    // island body itself stays near-black in every mode, like the hardware
    // island it's modelled on; light themes tint it, never whiten it.
    property color accent: blue
    // A theme change recolours the island as a 400 ms blend, not a cut.
    Behavior on accent { ColorAnimation { duration: 400; easing.type: Easing.OutCubic } }
    property color accentSoft: Qt.rgba(0.04, 0.52, 1, 0.5)
    // Text and glyphs that sit *on* the accent: dark on light accents, white on dark.
    readonly property color onAccent: (0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b) > 0.55 ? "#111114" : "#ffffff"
    property color themeBg: "#16161d"         // the palette's own background
    property color themeFg: "#ffffff"
    property var palette: []                   // a few swatches, for pickers
    property int colorMode: 0                  // 0 theme · 1 auto · 2 dark · 3 light
    property string themeName: ""
    readonly property string hydeThemes: Quickshell.env("HOME") + "/.config/hyde/themes/"

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
        if (!v.pry1 && !v["1xa7"]) return false;
        if (v["1xa7"]) accent = vivid(v["1xa7"]);
        if (v["1xa5"]) accentSoft = v["1xa5"];
        if (v.pry1) themeBg = v.pry1;
        if (v.txt1) themeFg = v.txt1;
        palette = ["pry1", "pry2", "1xa7", "2xa7", "3xa7", "4xa7"].filter(k => v[k]).map(k => v[k]);
        return true;
    }
    function fromKitty(text) {
        const v = {};
        for (const l of text.split("\n")) {
            const p = l.trim().split(/\s+/);
            if (p.length >= 2 && /^#[0-9A-Fa-f]{6}$/.test(p[1])) v[p[0]] = p[1];
        }
        if (!v.color4) return false;
        accent = vivid(v.color4);
        accentSoft = Qt.rgba(Qt.color(v.color4).r, Qt.color(v.color4).g, Qt.color(v.color4).b, 0.5);
        if (v.background) themeBg = v.background;
        if (v.foreground) themeFg = v.foreground;
        palette = ["background", "color1", "color3", "color2", "color6", "color4", "color5"].filter(k => v[k]).map(k => v[k]);
        return true;
    }
    function recolor() {
        if (colorMode === 0 && themeName) {
            if (themeDcol.loaded && fromDcol(parseDcol(themeDcol.text()))) return;
            if (themeKitty.loaded && fromKitty(themeKitty.text())) return;
        }
        if (wallDcol.loaded) fromDcol(parseDcol(wallDcol.text()));
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
    // Apple's own faces (/usr/share/fonts/apple-fonts):
    //   fontText     variable "SF Pro": opsz 17 (Text cut) → 28 (Display cut),
    //                set from the pixel size the way macOS does, so small UI
    //                text gets the Text design and titles the Display one
    //   fontRounded  "SF Pro Rounded" for numerals: counts, badges, the HUD
    //                value (Apple's widget and Control Center habit)
    //   fontGlyph    Symbols Nerd Font, never mixed into text runs
    // SF Compact (watchOS) and New York (serif) are installed but don't
    // belong in a desktop UI.
    readonly property string fontText: "SF Pro Text"          // static faces: see Label
    readonly property string fontDisplay: "SF Pro Display"
    readonly property string fontRounded: "SF Pro Rounded"
    readonly property string fontUi: fontText          // older name, same face
    readonly property string fontGlyph: "Symbols Nerd Font"
    readonly property string fontMono: "SF Mono"           // code and raw text

    // Apple's SF weights
    readonly property int wRegular: 400
    readonly property int wMedium: 510
    readonly property int wSemibold: 590
    readonly property int wBold: 700

    // Tracking (px) by size, from the fonts' own `trak` tables (track 0,
    // 1/2048 em per point size), which macOS applies and Qt doesn't.
    readonly property var trakSizes:   [6, 9, 10, 11, 12, 13, 14, 15, 16, 17, 20, 22, 24, 28, 32, 36, 50, 64, 80]
    readonly property var trakPro:     [82, 38, 24, 12, 0, -12, -22, -32, -40, -52, -46, -24, 6, 28, 26, 21, 14, 7, 0]
    readonly property var trakRounded: [174, 130, 116, 104, 92, 80, 70, 60, 52, 45, 37, 32, 29, 26, 24, 22, 14, 6, 0]
    function tracking(px, rounded) {
        const xs = trakSizes, ys = rounded ? trakRounded : trakPro;
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
    // own font face with its own glyph cache (and its own mapping of the 20 MB
    // variable font). Text 17 up to 19 px, a middle cut, Display from 25 px.
    function opszFor(px) { return px < 20 ? 17 : px < 25 ? 22 : 28; }

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
    readonly property int pressMs: 140          // press feedback (scale 0.97)
    readonly property int enterMs: 200          // small surfaces arriving, rows growing
    readonly property int exitMs: 150           // leaving: quicker than arriving
    readonly property int glideMs: 150          // values chasing a target (level fill, meters)
    readonly property int reflowMs: 200         // neighbours closing a gap
    readonly property int colorMs: 140
    readonly property int hoverMs: 80           // hover tints: answer the pointer at once
    readonly property int artMs: 400            // album-art colour following a new track
    readonly property int spinMs: 750           // one turn of a spinner: brisk (a faster turn reads as faster work; every spinner uses it)
    readonly property int stepMs: 600           // one step of a working ring (glides, then rests ~2.4 s)
    // The one beat every working ring on the notch steps to: T3's and an
    // update's moved on their own timers, so two rings side by side ticked
    // out of phase (a queue, not one rhythm). One wake every 3 s.
    readonly property int stepEvery: 3000
    property int step: 0
    property Timer stepClock: Timer { interval: root.stepEvery; repeat: true; running: !root.reduceMotion; onTriggered: root.step++ }
    readonly property int quickMs: 120          // a quick fade in place: tooltips, hints, a caret
    readonly property int microMs: 160          // a small state change in place: an icon's fill, a fade, a press
    readonly property int pulseMs: 520          // half a quick pulse (InOutSine there and back)
    readonly property int breatheMs: 700        // half a slow breath (a live mic, a waiting dot)
    // Hover timing, one set for the whole shell: things open after
    // Settings.hoverDelay (your setting), stay hoverLeaveMs after the pointer
    // leaves (crossing a gap doesn't close them), and tooltips wait tipMs
    // (slower than panels on purpose: no flashing as you cross the island).
    readonly property int hoverLeaveMs: 300
    readonly property int tipMs: 450
    // One loading sweep everywhere (Shimmer, the reasoning label, the notch's edge light): brisk, not drifting.
    readonly property int shimmerMs: 1300
    readonly property int hudInMs: 180          // the HUD answers a keypress: fast, 6px, no scale bounce
    readonly property int hudOutMs: 150
    readonly property int revealStepMs: 40      // stagger between groups of content (30–80ms)
    // Cards that grow out of the island (DeviceCard, AlarmCard).
    readonly property int cardInMs: 300         // the mark coming up
    readonly property int cardRiseMs: 260       // each line rising 4 px into place
    readonly property int ringDrawMs: 480       // a ring drawing itself closed
    readonly property int swingMs: 700          // a bell's damped swing, all of it
    readonly property int breathOutMs: 1100     // light breathing out of a ringing alarm

    // Reduced motion: fewer and gentler: fades and colour stay, travel,
    // scale and stagger go. On when you switch it on (Controls → Reduce
    // Motion, remembered in ~/.local/state/rice/prefs.json), when
    // RICE_REDUCE_MOTION=1, or when Hyprland's own animations are off.
    readonly property bool reduceMotion: prefs.reduceMotion || envReduce || hyprStill
    readonly property bool envReduce: Quickshell.env("RICE_REDUCE_MOTION") === "1"
    property bool hyprStill: false
    function setReduceMotion(on) { prefs.reduceMotion = on; }
    Process {
        running: true
        command: ["hyprctl", "getoption", "animations:enabled", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { if (JSON.parse(text).int === 0) root.hyprStill = true; } catch (e) {}
            }
        }
    }
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rice/prefs.json"
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
    readonly property var surfaceIn: ({ stiffness: 300, damping: 34.6 })
    readonly property var surfaceOut: ({ stiffness: 380, damping: 39 })
    readonly property var surfaceKeyIn: ({ stiffness: 560, damping: 47.3 })
    readonly property var surfaceKeyOut: ({ stiffness: 640, damping: 50.6 })

    // ── Toast stack: Sonner's numbers (emilkowalski/sonner, refs/) ───────
    readonly property int toastWidth: 368        // Sonner 356; ours carries an icon
    readonly property int stackGap: 14           // GAP
    readonly property int stackVisible: 3        // VISIBLE_TOASTS_AMOUNT
    readonly property real stackScaleStep: 0.05  // each toast behind is 5% smaller
    readonly property int stackMs: 400           // transform/opacity/height transition
    readonly property var easeCss: [0.25, 0.1, 0.25, 1, 1, 1]     // CSS `ease`
    readonly property var easeOutCss: [0, 0, 0.58, 1, 1, 1]       // CSS `ease-out`
    readonly property int swipeThreshold: 45     // px, or…
    readonly property real swipeVelocity: 0.11   // px/ms averaged over the gesture (Sonner's; the lock screen's own check)
    readonly property real swipeFlick: 0.5       // px/ms at release (components/Fling): a flick dismisses on its own
    readonly property int swipeOutMs: 200
    readonly property int unmountMs: 200         // TIME_BEFORE_UNMOUNT
    // Movement the wrong way is damped, not blocked, so it feels elastic.
    function swipeDamp(d) {
        const damped = d / (1.5 + Math.abs(d) / 20);
        return Math.abs(damped) < Math.abs(d) ? damped : d;
    }

    // ── Layout ───────────────────────────────────────────────────────────
    readonly property int barGap: 6             // distance below Waybar's exclusive zone
}
