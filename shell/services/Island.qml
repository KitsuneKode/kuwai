pragma Singleton

// What the island is showing beyond the bar: one panel at a time ("" when
// none), on one screen. Panels grow out of the island (docs/ISLAND.md):
// calendar from the clock, the power menu (Super+Backspace), the launcher (Super+A).
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

    readonly property var panels: ["calendar", "power", "launcher"]
    property string panel: ""
    property string screen: ""
    // "key" opens without the grow (Emil: never animate what a key does
    // a hundred times a day); "pointer" grows out of the island.
    property string via: "pointer"

    function open(name, screenName, how) {
        if (panels.indexOf(name) < 0) return;
        screen = screenName || Screens.focusedName;
        via = how === "key" ? "key" : "pointer";
        panel = name;
    }
    function close() { panel = ""; }
    function toggle(name, screenName, how) {
        const s = screenName || Screens.focusedName;
        if (panel === name && screen === s) close();
        else open(name, s, how);
    }

    IpcHandler {
        target: "island"
        function toggle(panel: string): void { root.toggle(panel, "", "key"); }
        function open(panel: string): void { root.open(panel, "", "key"); }
        function close(): void { root.close(); }
        function state(): string { return root.panel ? root.panel + " " + root.screen : "none"; }
    }
}
