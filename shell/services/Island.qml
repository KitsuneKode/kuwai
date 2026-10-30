pragma Singleton

// What the island is showing beyond the bar: one panel at a time ("" when
// none), on one screen. Panels grow out of the island (docs/ISLAND.md):
// calendar from the clock, the power menu (Super+Backspace), the launcher (Super+A),
// settings (Super+Ctrl+I).
//
//   Island.toggle("calendar", "DP-3")     qs ipc call island toggle power
//
// Opening needs no island bar: with Waybar still in charge the island is
// hidden at rest and only appears, under Waybar, to hold the panel.
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var panels: ["calendar", "power", "launcher", "settings", "system", "theme", "keys"]
    property string panel: ""
    property string screen: ""
    // "key" opens without the grow (Emil: never animate what a key does
    // a hundred times a day); "pointer" grows out of the island.
    property string via: "pointer"

    // Panels opened from another panel remember where they came from: a
    // back chevron (or a right click, or the mouse's back button) returns.
    property var history: []
    readonly property bool canBack: history.length > 0

    // `from` "island": opened from the island itself (its clock, rings…);
    // going back returns to it, expanded while the pointer is still there.
    function open(name, screenName, how, from) {
        if (panels.indexOf(name) < 0) return;
        const s = screenName || Screens.focusedName;
        history = panel && panel !== name && s === screen ? [...history, panel] : from === "island" ? ["island"] : [];
        screen = s;
        via = how === "key" ? "key" : "pointer";
        panel = name;
    }
    function back() {
        if (!history.length) { close(); return; }
        const h = history.slice();
        const to = h.pop();
        if (to === "island") { close(); return; }
        panel = to;
        history = h;
    }
    function close() { panel = ""; history = []; }
    // The launcher's last search, kept between openings (selected, so typing replaces it).
    property string lastQuery: ""
    // The theme picker's tab: "themes" or "wallpapers".
    property string themeMode: "themes"
    function themes(mode) {
        themeMode = mode;
        if (panel === "theme" && screen === Screens.focusedName) close();
        // Used now and then (not a hundred times a day), so it grows open
        // even from the keyboard: the motion shows where it came from.
        else open("theme", "", "pointer");
    }
    function toggle(name, screenName, how) {
        const s = screenName || Screens.focusedName;
        if (panel === name && screen === s) close();
        else open(name, s, how);
    }

    // ── Launcher frecency ────────────────────────────────────────────────
    // Lives here, not in the launcher: a panel is destroyed the moment it
    // closes, and an async file save finishing into a destroyed object
    // crashed the whole shell (three times, 2026-10-29). Plain text JSON,
    // no JsonAdapter `var` (that path was in the crash too).
    property var uses: ({})
    FileView {
        id: usesFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rice/launcher.json"
        printErrors: false
        onLoaded: { try { const d = JSON.parse(text()); root.uses = d.counts || d || {}; } catch (e) { root.uses = {}; } }
    }
    Timer { id: usesSave; interval: 800; onTriggered: usesFile.setText(JSON.stringify({ counts: root.uses })) }
    function frecency(id) {
        const u = uses[id];
        if (!u) return 0;
        return u.n / (1 + (Date.now() - u.t) / 86400000 / 7);
    }
    function used(id) {
        const c = Object.assign({}, uses);
        const u = c[id] || { n: 0, t: 0 };
        c[id] = { n: u.n + 1, t: Date.now() };
        uses = c;
        usesSave.restart();
    }

    IpcHandler {
        target: "island"
        function toggle(panel: string): void { root.toggle(panel, "", "key"); }
        function open(panel: string): void { root.open(panel, "", "key"); }
        function close(): void { root.close(); }
        function back(): void { root.back(); }
        function themes(mode: string): void { root.themes(mode || "themes"); }
        function state(): string { return root.panel ? root.panel + " " + root.screen : "none"; }
    }
}
