pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: fonts

    readonly property var installedFonts: Qt.fontFamilies()
    readonly property string systemFamily: Qt.application.font.family || "sans-serif"
    readonly property string interFamily: hasFont("Inter") && hasFont("Inter Display") ? "Inter"
                                        : hasFont("Inter Variable") ? "Inter Variable"
                                        : hasFont("Inter") ? "Inter" : ""
    readonly property bool hasSfText: hasFont("SF Pro Text")
    readonly property bool hasSfDisplay: hasFont("SF Pro Display")
    readonly property bool hasSfRounded: hasFont("SF Pro Rounded")
    readonly property bool hasSfCompactText: hasFont("SF Compact Text")
    readonly property bool hasSfCompactRounded: hasFont("SF Compact Rounded")
    readonly property bool hasSfMono: hasFont("SF Mono")
    readonly property bool hasSf: hasSfText && hasSfDisplay
    readonly property bool hasSfRoundedProfile: hasSfText && hasSfRounded

    FontLoader { id: geist400; source: Qt.resolvedUrl("../assets/fonts/Geist-Regular.ttf") }
    FontLoader { id: geist500; source: Qt.resolvedUrl("../assets/fonts/Geist-Medium.ttf") }
    FontLoader { id: geist600; source: Qt.resolvedUrl("../assets/fonts/Geist-SemiBold.ttf") }
    FontLoader { id: geist700; source: Qt.resolvedUrl("../assets/fonts/Geist-Bold.ttf") }
    FontLoader { id: geistMono400; source: Qt.resolvedUrl("../assets/fonts/GeistMono-Regular.ttf") }
    FontLoader { id: geistMono500; source: Qt.resolvedUrl("../assets/fonts/GeistMono-Medium.ttf") }

    readonly property bool geistReady: geist400.status === FontLoader.Ready && geist500.status === FontLoader.Ready && geist600.status === FontLoader.Ready && geist700.status === FontLoader.Ready
    readonly property bool geistMonoReady: geistMono400.status === FontLoader.Ready && geistMono500.status === FontLoader.Ready

    readonly property var profiles: ({
        "sf-rounded": { text: "SF Pro Text", display: hasSfDisplay ? "SF Pro Display" : "SF Pro Text", rounded: "SF Pro Rounded", compact: hasSfCompactText ? "SF Compact Text" : "SF Pro Text", compactRounded: hasSfCompactRounded ? "SF Compact Rounded" : "SF Pro Rounded", tracking: "sf" },
        "sf": { text: "SF Pro Text", display: "SF Pro Display", rounded: "SF Pro Text", compact: hasSfCompactText ? "SF Compact Text" : "SF Pro Text", compactRounded: hasSfCompactText ? "SF Compact Text" : "SF Pro Text", tracking: "sf" },
        "geist": { text: "Kuwai Geist 400", display: "Kuwai Geist 400", rounded: "Kuwai Geist 600", compact: "Kuwai Geist 400", compactRounded: "Kuwai Geist 600", tracking: "geist" },
        "inter": { text: interFamily, display: interFamily === "Inter" && hasFont("Inter Display") ? "Inter Display" : interFamily, rounded: interFamily, compact: interFamily, compactRounded: interFamily, tracking: "none" },
        "system": { text: systemFamily, display: systemFamily, rounded: systemFamily, compact: systemFamily, compactRounded: systemFamily, tracking: "none" }
    })

    function hasFont(name) { return name !== "" && installedFonts.indexOf(name) >= 0 }
    function firstFont(names) {
        for (let i = 0; i < names.length; i++) if (hasFont(names[i])) return names[i];
        return "";
    }
    function geistFamily(weight) {
        const w = weight || 400;
        if (w >= 650) return "Kuwai Geist 700";
        if (w >= 550) return "Kuwai Geist 600";
        if (w >= 450) return "Kuwai Geist 500";
        return "Kuwai Geist 400";
    }
    function geistMonoFamily(weight) { return (weight || 400) >= 450 ? "Kuwai Geist Mono 500" : "Kuwai Geist Mono 400" }

    readonly property string requestedProfile: {
        const env = (Quickshell.env("KUWAI_FONT") || "").toLowerCase();
        if (["sf-rounded", "sf", "geist", "inter", "system"].indexOf(env) >= 0) return env;
        return Settings.fontProfile;
    }
    function resolveProfile(want) {
        if (want === "system") return "system";
        if ((want === "sf-rounded" || want === "auto") && hasSfRoundedProfile) return "sf-rounded";
        if ((want === "sf-rounded" || want === "sf" || want === "auto") && hasSf) return "sf";
        if (want === "inter" && interFamily) return "inter";
        return geistReady ? "geist" : "system";
    }
    readonly property string profile: resolveProfile(requestedProfile)
    readonly property var record: profiles[profile] || profiles.system

    function textFamily(weight) { return profile === "geist" ? geistFamily(weight) : record.text }
    function displayFamily(weight) { return profile === "geist" ? geistFamily(weight) : record.display }
    function roundedFamily(weight) { return profile === "geist" ? geistFamily(weight) : record.rounded }
    function compactFamily(weight) { return profile === "geist" ? geistFamily(weight) : record.compact }
    function compactRoundedFamily(weight) { return profile === "geist" ? geistFamily(weight) : record.compactRounded }

    readonly property var sfTrackSizes: [6, 9, 10, 11, 12, 13, 14, 15, 16, 17, 20, 22, 24, 28, 32, 36, 50, 64, 80]
    readonly property var sfTrackPro: [82, 38, 24, 12, 0, -12, -22, -32, -40, -52, -46, -24, 6, 28, 26, 21, 14, 7, 0]
    readonly property var sfTrackRounded: [174, 130, 116, 104, 92, 80, 70, 60, 52, 45, 37, 32, 29, 26, 24, 22, 14, 6, 0]
    readonly property var sfTrackCompactSizes: [6, 7, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 25, 36.5, 44, 77]
    readonly property var sfTrackCompact: [100, 60, 60, 48, 40, 32, 28, 8, 0, -8, -16, -24, 0, -20, -40, -40, -50]
    readonly property var geistTrackSizes: [16, 32, 48, 96]
    readonly property var geistTrackEm: [0, -0.01, -0.02, -0.035]
    function interpolate(xs, ys, px) {
        if (px <= xs[0]) return ys[0];
        for (let k = 1; k < xs.length; k++) {
            if (px <= xs[k]) {
                const t = (px - xs[k - 1]) / (xs[k] - xs[k - 1]);
                return ys[k - 1] + (ys[k] - ys[k - 1]) * t;
            }
        }
        return ys[ys.length - 1];
    }
    function geistTracking(px) { return interpolate(geistTrackSizes, geistTrackEm, px) * px }
    function sfTracking(px, rounded, compact) {
        if (compact && (rounded ? hasSfCompactRounded : hasSfCompactText))
            return interpolate(sfTrackCompactSizes, sfTrackCompact, px) / 2048 * px;
        const ys = rounded && profile === "sf-rounded" ? sfTrackRounded : sfTrackPro;
        return interpolate(sfTrackSizes, ys, px) / 2048 * px;
    }
    function tracking(px, rounded, compact) {
        if (profile === "geist") return geistTracking(px);
        if (record.tracking === "sf") return sfTracking(px, rounded, compact);
        return 0;
    }

    function monoFor(weight) {
        const want = Settings.monoFont;
        const geist = geistMonoReady ? geistMonoFamily(weight) : "monospace";
        if (want === "geist-mono") return geist;
        if (want === "sf-mono") return hasSfMono ? "SF Mono" : geist;
        if (want === "monolisa") return firstFont(["MonoLisa", "MonoLisa Nerd Font"]) || geist;
        if (want === "dank-mono") return firstFont(["Dank Mono", "DankMono Nerd Font", "DankMono Nerd Font Mono"]) || geist;
        if (want === "jetbrains") return firstFont(["JetBrains Mono", "JetBrainsMono Nerd Font", "JetBrainsMono NF"]) || geist;
        if (want === "maple") return firstFont(["Maple Mono", "Maple Mono NF", "Maple Mono Nerd Font"]) || geist;
        if (want === "iosevka") return firstFont(["Iosevka", "Iosevka Nerd Font", "IosevkaTerm Nerd Font"]) || geist;
        return (profile === "sf" || profile === "sf-rounded") && hasSfMono ? "SF Mono" : geist;
    }
    readonly property string mono: monoFor(400)

    readonly property string clockFace: {
        const want = Settings.clockFont;
        if (want === "geist") return geistReady ? geistFamily(600) : systemFamily;
        if (want === "sf-display") return hasSfDisplay ? "SF Pro Display" : (geistReady ? geistFamily(600) : systemFamily);
        if (want === "sf-rounded") return hasSfRounded ? "SF Pro Rounded" : (geistReady ? geistFamily(600) : systemFamily);
        return hasSfRounded ? "SF Pro Rounded" : geistReady ? geistFamily(600) : systemFamily;
    }
    readonly property bool clockIsGeist: clockFace === geistFamily(600)
    function clockTracking(px) {
        if (clockIsGeist) return -0.045 * px;
        if (clockFace === "SF Pro Rounded") return sfTracking(px, true);
        if (clockFace === "SF Pro Display" || clockFace === "SF Pro Text") return sfTracking(px, false);
        return 0;
    }
}
