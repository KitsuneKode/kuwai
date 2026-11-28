pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

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

    property color accent: blue
    Behavior on accent { ColorAnimation { duration: 400; easing.type: Easing.OutCubic } }
    function luminance(c) {
        function linear(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b);
    }
    function contrastInk(c) {
        const y = luminance(c);
        return (y + 0.05) / 0.05 >= 1.05 / (y + 0.05) ? "#000000" : "#ffffff";
    }
    readonly property color onAccent: contrastInk(accent)
    readonly property color onDanger: contrastInk(red)
    property int colorMode: 0
    property string themeName: ""
    readonly property string home: Quickshell.env("HOME")

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
    function lookAccent(text) {
        try {
            const d = JSON.parse(text);
            return d && d.schema === 1 && d.role && typeof d.role.accent === "string" && /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(d.role.accent) ? d.role.accent : "";
        } catch (e) {
            return "";
        }
    }
    function recolor() {
        const look = kuwaiLook.ok ? lookAccent(kuwaiLook.text()) : "";
        if (look) { accent = Qt.color(look); return; }
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
        id: kuwaiLook
        property bool ok: false
        path: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/kuwai/look/current/palette.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { ok = true; root.recolor(); }
        onLoadFailed: { ok = false; root.recolor(); }
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

    readonly property var installedFonts: Qt.fontFamilies()
    function hasFont(name) { return installedFonts.indexOf(name) >= 0; }
    readonly property bool hasSf: hasFont("SF Pro Text") && hasFont("SF Pro Display")
    readonly property string interFamily: hasFont("Inter") && hasFont("Inter Display") ? "Inter"
                                        : hasFont("Inter Variable") ? "Inter Variable"
                                        : hasFont("Inter") ? "Inter"
                                        : hasFont("Inter 28pt") ? "Inter 28pt" : ""
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
                                        : fontKind === "inter" && interFamily === "Inter" && hasFont("Inter 28pt") ? "Inter 28pt"
                                        : fontText
    readonly property bool roundedFace: fontKind === "sf" && hasFont("SF Pro Rounded")
    readonly property string fontRounded: roundedFace ? "SF Pro Rounded" : fontText
    readonly property string fontGlyph: "Symbols Nerd Font"
    readonly property string fontMono: hasFont("SF Mono") ? "SF Mono" : hasFont("Geist Mono") ? "Geist Mono" : hasFont("JetBrains Mono") ? "JetBrains Mono" : "monospace"
    readonly property bool fontOpszAxis: fontKind === "inter" && interFamily === "Inter Variable"
    readonly property int wRegular: 400
    readonly property int wMedium: 510
    readonly property int wSemibold: 590
    readonly property int wBold: 700
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
    function opszFor(px) {
        if (fontKind === "inter") return px < 20 ? 14 : px < 25 ? 22 : 32;
        return px < 20 ? 17 : px < 25 ? 22 : 28;
    }
    readonly property var noAxes: ({})
    function axesFor(px) { return fontOpszAxis ? { "opsz": opszFor(px) } : noAxes; }

    readonly property real textScale: Math.max(0.85, Math.min(2, prefsTextScale || 1))
    property real prefsTextScale: 1
    function sp(n) { return Math.round(n * textScale); }

    readonly property var easeOut: [0.23, 1, 0.32, 1, 1, 1]
    readonly property int pressMs: 140
    readonly property var springFast: ({ stiffness: 13300, damping: 231, exitMs: 60 })
    readonly property var springModerate: ({ stiffness: 3329, damping: 115, exitMs: 120 })
    readonly property var springSlow: ({ stiffness: 1069, damping: 57.5, exitMs: 160 })

    readonly property bool reduceMotion: prefsReduce || Quickshell.env("KUWAI_REDUCE_MOTION") === "1"
    property bool prefsReduce: false
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/kuwai/prefs.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.prefsReduce = !!d.reduceMotion;
                const s = Number(d.textScale);
                root.prefsTextScale = Number.isFinite(s) ? s : 1;
            } catch (e) {}
        }
    }
}
