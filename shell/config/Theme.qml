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
    // ── Material ─────────────────────────────────────────────────────────
    // One glass, the voxtype HUD's: near-black #111114 over the compositor's
    // blur (components/GlassCard draws the ring, sheen and hairline).
    readonly property color glassTint: Qt.rgba(0.067, 0.067, 0.078, 0.58)
    // Text-heavy cards (toasts) sit over anything: a little denser, so body
    // copy stays readable over busy windows.
    readonly property color glassTintThick: Qt.rgba(0.067, 0.067, 0.078, 0.68)
    // Floating menus (the center, the island): the same glass, denser still,
    // with a deep shadow under it; it reads as raised, not as a lighter grey.
    readonly property color glassTintElevated: Qt.rgba(0.067, 0.067, 0.078, 0.74)
    readonly property color platter: Qt.rgba(1, 1, 1, 0.15)
    readonly property color platterDim: Qt.rgba(1, 1, 1, 0.08)
    readonly property color track: Qt.rgba(1, 1, 1, 0.18)
    readonly property color fill: Qt.rgba(1, 1, 1, 0.96)
    readonly property color fillDim: Qt.rgba(1, 1, 1, 0.32)
    readonly property color pill: Qt.rgba(1, 1, 1, 0.12)
    readonly property color pillHover: Qt.rgba(1, 1, 1, 0.22)

    // ── Text ─────────────────────────────────────────────────────────────
    // Over blur, flat grey washes out: keep secondary/tertiary brighter than
    // on a solid surface (vibrancy), and lean on weight for hierarchy.
    readonly property color textPrimary: Qt.rgba(1, 1, 1, 0.96)
    readonly property color textSecondary: Qt.rgba(1, 1, 1, 0.72)
    readonly property color textTertiary: Qt.rgba(1, 1, 1, 0.50)
    readonly property color textDim: Qt.rgba(1, 1, 1, 0.55)

    // Apple's dark-mode system colours: tuned to read on dark material.
    readonly property color red: "#ff453a"
    readonly property color orange: "#ff9f0a"
    readonly property color yellow: "#ffd60a"
    readonly property color green: "#30d158"
    readonly property color blue: "#0a84ff"
    readonly property color positive: green
    readonly property color caution: orange
    readonly property color critical: red

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
    readonly property string fontText: "SF Pro"
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
    function opszFor(px) { return Math.max(17, Math.min(28, px)); }

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
    readonly property int hudInMs: 180          // the HUD answers a keypress: fast, 6px, no scale bounce
    readonly property int hudOutMs: 150
    readonly property int revealStepMs: 40      // stagger between groups of content (30–80ms)

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

    // ── Toast stack: Sonner's numbers (emilkowalski/sonner, refs/) ───────
    readonly property int toastWidth: 368        // Sonner 356; ours carries an icon
    readonly property int stackGap: 14           // GAP
    readonly property int stackVisible: 3        // VISIBLE_TOASTS_AMOUNT
    readonly property real stackScaleStep: 0.05  // each toast behind is 5% smaller
    readonly property int stackMs: 400           // transform/opacity/height transition
    readonly property var easeCss: [0.25, 0.1, 0.25, 1, 1, 1]     // CSS `ease`
    readonly property var easeOutCss: [0, 0, 0.58, 1, 1, 1]       // CSS `ease-out`
    readonly property int swipeThreshold: 45     // px, or…
    readonly property real swipeVelocity: 0.11   // px/ms averaged over the gesture
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
