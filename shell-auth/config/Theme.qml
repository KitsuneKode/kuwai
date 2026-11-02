// The password prompt's own design tokens: the subset of shell/config/Theme.qml
// it uses, kept as a reviewed copy (not a link) so nothing added to the shell
// later can end up running next to your password. Rule for shell-auth/: read
// files and draw, nothing else (no Process, sockets, network, IPC). `kuwai
// doctor` checks it; `kuwai auth diff` shows where it drifted from the shell.
//
// Same look as the island: SF Pro at Apple's optical sizes and tracking, the
// same greys, and the theme's accent from the same files (HyDE's colour mode:
// the theme's theme.dcol → its kitty.theme, or the wallpaper's wall.dcol).
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ── Material and text ────────────────────────────────────────────────
    readonly property color glassTint: Qt.rgba(0.067, 0.067, 0.078, 0.58)
    readonly property color pill: Qt.rgba(1, 1, 1, 0.12)
    readonly property color pillHover: Qt.rgba(1, 1, 1, 0.22)
    readonly property color textPrimary: Qt.rgba(1, 1, 1, 0.96)
    readonly property color textSecondary: Qt.rgba(1, 1, 1, 0.72)
    readonly property color textTertiary: Qt.rgba(1, 1, 1, 0.50)
    readonly property color red: "#ff453a"
    readonly property color orange: "#ff9f0a"
    readonly property color green: "#30d158"
    readonly property color blue: "#0a84ff"

    // ── The theme's accent (files only) ──────────────────────────────────
    property color accent: blue
    Behavior on accent { ColorAnimation { duration: 400; easing.type: Easing.OutCubic } }
    readonly property color onAccent: (0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b) > 0.55 ? "#111114" : "#ffffff"
    property int colorMode: 0
    property string themeName: ""
    readonly property string home: Quickshell.env("HOME")

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
    function dcolAccent(text) {
        const m = text.match(/^dcol_1xa7="([0-9A-Fa-f]{6})"$/m);
        return m ? "#" + m[1] : "";
    }
    function kittyAccent(text) {
        const m = text.match(/^\s*color4\s+(#[0-9A-Fa-f]{6})\s*$/m);
        return m ? m[1] : "";
    }
    function recolor() {
        let a = "";
        if (colorMode === 0 && themeName) {
            if (themeDcol.ok) a = dcolAccent(themeDcol.text());
            if (!a && themeKitty.ok) a = kittyAccent(themeKitty.text());
        }
        if (!a && wallDcol.ok) a = dcolAccent(wallDcol.text());
        if (a) accent = vivid(a);
    }
    FileView {
        path: root.home + "/.local/state/hyde/staterc"
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
        property bool ok: false
        path: root.themeName ? root.home + "/.config/hyde/themes/" + root.themeName + "/theme.dcol" : ""
        printErrors: false
        onPathChanged: ok = false
        onLoaded: { ok = true; root.recolor(); }
        onLoadFailed: { ok = false; root.recolor(); }
    }
    FileView {
        id: themeKitty
        property bool ok: false
        path: root.themeName ? root.home + "/.config/hyde/themes/" + root.themeName + "/kitty.theme" : ""
        printErrors: false
        onPathChanged: ok = false
        onLoaded: { ok = true; root.recolor(); }
        onLoadFailed: { ok = false; root.recolor(); }
    }
    FileView {
        id: wallDcol
        property bool ok: false
        path: root.home + "/.cache/hyde/wall.dcol"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { ok = true; root.recolor(); }
    }

    // ── Type (Apple's faces, optical sizes, tracking) ────────────────────
    readonly property string fontText: "SF Pro Text"          // static faces: see Label
    readonly property string fontDisplay: "SF Pro Display"
    readonly property string fontRounded: "SF Pro Rounded"
    readonly property string fontGlyph: "Symbols Nerd Font"
    readonly property string fontMono: "SF Mono"
    readonly property int wRegular: 400
    readonly property int wMedium: 510
    readonly property int wSemibold: 590
    readonly property int wBold: 700
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
    function opszFor(px) { return px < 20 ? 17 : px < 25 ? 22 : 28; }

    // ── Motion ───────────────────────────────────────────────────────────
    readonly property var easeOut: [0.23, 1, 0.32, 1, 1, 1]
    readonly property int pressMs: 140
    readonly property var springFast: ({ stiffness: 13300, damping: 231, exitMs: 60 })
    readonly property var springModerate: ({ stiffness: 3329, damping: 115, exitMs: 120 })
    readonly property var springSlow: ({ stiffness: 1069, damping: 57.5, exitMs: 160 })

    // Reduced motion: the shell's switch (read-only here) or the env var.
    readonly property bool reduceMotion: prefsReduce || Quickshell.env("RICE_REDUCE_MOTION") === "1"
    property bool prefsReduce: false
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/rice/prefs.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.prefsReduce = !!JSON.parse(text()).reduceMotion; } catch (e) {} }
    }
}
