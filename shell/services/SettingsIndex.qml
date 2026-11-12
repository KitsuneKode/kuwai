pragma Singleton

// The Settings panel's pages and the words that find them, so the launcher
// can open Settings on the right page ("idle", "screensaver", "24-hour").
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import qs.config

Singleton {
    readonly property var sections: [
        { id: "bar", keys: "top bar waybar notch shape workspaces at rest battery signal music weather hover delay now playing", label: "Bar & Island", glyph: "\u{f0d6f}", tint: "#0a84ff" },
        { id: "clock", keys: "clock 24-hour time seconds date", label: "Clock & Date", glyph: "\u{f0954}", tint: "#ff9f0a" },
        { id: "notifs", keys: "notifications do not disturb dnd focus toast where they appear clear seen", label: "Notifications", glyph: "\u{f009a}", tint: "#ff453a" },
        { id: "assistant", keys: "assistant ai agent opt in local ollama diagnose crash", label: "Assistant", glyph: "\u{f06a9}", tint: "#5e5ce6" },
        { id: "motion", keys: "reduce motion animation accessibility contrast transparency text size larger bigger", label: "Accessibility & Motion", glyph: "\u{f0e7d}", tint: "#bf5af2" },
        { id: "keyboard", keys: "keyboard layout language input method ime fcitx ibus switch layouts typing", label: "Keyboard", glyph: "\u{f030c}", tint: Theme.gray },
        { id: "island", keys: "island style minimal hidden everything reveal approach proximity quick switch caffeine", label: "Island", glyph: "\u{f0d6f}", tint: "#ff9f0a" },
        { id: "workspaces", keys: "workspaces screens monitors desktops pills keys", label: "Workspaces", glyph: "\u{f0570}", tint: "#5e5ce6" },
        { id: "power", keys: "power idle dim lock screen off sleep battery hypridle suspend caffeine music", label: "Power & Idle", glyph: "\u{f0425}", tint: "#30d158" },
        { id: "saver", keys: "screensaver dusk live wallpaper still battery", label: "Screensaver", glyph: "\u{f0379}", tint: "#5e5ce6" },
        { id: "time", keys: "reminders alarms wake notes pomodoro focus timer", label: "Reminders & Alarms", glyph: "\u{f0020}", tint: "#ff9f0a" },
        { id: "clipboard", keys: "clipboard pins history secrets", label: "Clipboard", glyph: "\u{f014c}", tint: "#64d2ff" },
        { id: "updates", keys: "software update aur flatpak check packages", label: "Software Update", glyph: "\u{f06b0}", tint: "#30d158" },
        { id: "about", keys: "about restart version shell", label: "About", glyph: "\u{f02fd}", tint: "#8e8e93" }
    ]
    // Pages whose label or words match every word of q, best first.
    function search(q) {
        const words = String(q || "").toLowerCase().trim().split(/\s+/).filter(w => w.length > 1);
        if (!words.length) return [];
        return sections.map(x => {
            const hay = (x.label + " " + x.keys).toLowerCase();
            if (!words.every(w => hay.includes(w))) return null;
            return { section: x, score: words.reduce((n, w) => n + (x.label.toLowerCase().includes(w) ? 3 : 1), 0) };
        }).filter(Boolean).sort((a, b) => b.score - a.score).map(r => r.section);
    }
}
