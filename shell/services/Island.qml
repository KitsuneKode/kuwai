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
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    readonly property var panels: ["calendar", "power", "launcher", "settings", "system", "theme", "keys", "switcher", "updates"]
    property string panel: ""
    // Each screen's island width at rest, so other surfaces (the clipboard,
    // toasts) can grow out of exactly its shape. Set by IslandBar.
    property var restWidths: ({})
    function setRestWidth(screenName, w) {
        if (!screenName || restWidths[screenName] === w) return;
        const m = Object.assign({}, restWidths);
        m[screenName] = w;
        restWidths = m;
    }
    // The island's resting shape per screen, published for kuwai's password
    // prompt (shell-auth/, its own process) so it can grow out of exactly this
    // shape: $XDG_RUNTIME_DIR/rice/island.json (tmpfs, this user only).
    property var restShapes: ({})
    function setRestShape(screenName, w, h, top, notch) {
        if (!screenName) return;
        const cur = restShapes[screenName];
        if (cur && cur.w === w && cur.h === h && cur.top === top && cur.notch === notch) return;
        const m = Object.assign({}, restShapes);
        m[screenName] = { w: w, h: h, top: top, notch: notch };
        restShapes = m;
        publish.restart();
    }
    Timer {
        id: publish
        interval: 400
        onTriggered: shapeFile.setText(JSON.stringify({ screens: root.restShapes }))
    }
    FileView {
        id: shapeFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice/island.json"
        printErrors: false
        atomicWrites: true
    }
    // kuwai's workspace model (features.lua `desktops`): "desktops" (every
    // screen switches together; one row of pills everywhere), "per_screen",
    // or "global". Read from kuwai's state file.
    property string workspaceModel: "per_screen"
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/kuwai/state"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { const m = text().match(/^workspace_model=(\S+)/m); root.workspaceModel = m ? m[1] : "per_screen"; }
    }
    readonly property bool desktops: workspaceModel === "desktops"
    property string screen: ""
    // "key" opens without the grow (Emil: never animate what a key does
    // a hundred times a day); "pointer" grows out of the island.
    property string via: "pointer"

    // Panels opened from another panel remember where they came from: a
    // back chevron (or a right click, or the mouse's back button) returns.
    property var history: []
    // A panel with its own levels (Updates → a package's review) takes the
    // one Back row: it sets innerBack to a function and innerBackLabel to where
    // it leads, so there is never a second back button inside the panel.
    property var innerBack: null
    property string innerBackLabel: ""
    readonly property bool canBack: history.length > 0 || innerBack !== null

    // `from` "island": opened from the island itself (its clock, rings…);
    // going back returns to it, expanded while the pointer is still there.
    function open(name, screenName, how, from) {
        if (panels.indexOf(name) < 0) return;
        // From a key (no screen given): ask Hyprland where you are first.
        if (!screenName) { Screens.refresh(n => root.openOn(name, n, how, from)); return; }
        openOn(name, screenName, how, from);
    }
    function openOn(name, screenName, how, from) {
        const s = screenName || Screens.focusedName;
        history = panel && panel !== name && s === screen ? [...history, panel] : from === "island" ? ["island"] : [];
        screen = s;
        via = how === "key" ? "key" : "pointer";
        panel = name;
    }
    function back() {
        if (innerBack) { innerBack(); return; }
        if (!history.length) { close(); return; }
        const h = history.slice();
        const to = h.pop();
        if (to === "island") { close(); return; }
        panel = to;
        history = h;
    }
    // Same for the island's panels (not the switcher: it decides on Alt-up).
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "openwindow" && root.panel && root.panel !== "switcher") root.close(); }
    }
    function close() { panel = ""; history = []; innerBack = null; innerBackLabel = ""; }
    // The launcher's last search, kept between openings (selected, so typing replaces it).
    property string lastQuery: ""
    // A mode to open the launcher in (":" emoji, ";" glyphs): placed with the
    // cursor after it, not selected, so typing continues the search.
    property string prefill: ""
    function openWith(prefix) { prefill = prefix; open("launcher", "", "key"); }
    // The theme picker's tab: "themes" or "wallpapers".
    property string themeMode: "themes"
    function themes(mode) {
        themeMode = mode;
        // Used now and then (not a hundred times a day), so it grows open
        // even from the keyboard: the motion shows where it came from.
        Screens.refresh(n => {
            if (root.panel === "theme" && root.screen === n) root.close();
            else root.openOn("theme", n, "pointer");
        });
    }
    function toggle(name, screenName, how) {
        const go = s => {
            if (root.panel === name && root.screen === s) root.close();
            else root.openOn(name, s, how);
        };
        if (screenName) go(screenName); else Screens.refresh(go);
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
