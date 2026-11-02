pragma Singleton

// The window switcher's state (the panel is modules/island/SwitcherPanel).
//
//   Alt+Tab        hold Alt, tap Tab to step; let go of Alt to switch
//   Alt+Shift+Tab  step back             Alt+`   only the focused app's windows
//   Super+Alt+Tab  only this workspace's windows (snappy-switcher's --workspace)
//   a quick flick  (Alt released within 140 ms) switches without any UI
//   in the panel   ←→ step · ↵ switch · Esc cancel · Q close the selected
//                  window · W only this workspace · hover picks, click switches
//
// kuwai (hypr/kuwai/binds.lua) sends rice:switch-next / -prev / -app on the
// keys and rice:switch-commit when Alt comes up; the global shortcuts live in
// modules/Shortcuts.qml. Most-recently-used order is kept here from Hyprland's
// focus events as they happen, so opening needs no IPC round trip.
//
// Ported from snappy-switcher's good parts: MRU order, hold-and-release, the
// silent quick switch, follow the focused monitor, a current-workspace
// filter, icons with a letter fallback — plus live previews and app cycling.

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    property bool active: false        // between the first Tab and commit/cancel
    property bool shown: false         // the panel is up (after the flick window)
    property bool appOnly: false
    property bool workspaceOnly: false
    property string appClass: ""
    property int index: 0

    // ── MRU, from focus events ───────────────────────────────────────────
    property var mru: []               // addresses, most recent first
    // From Hyprland's own focus event (activewindowv2>>ADDRESS): authoritative
    // and immediate, unlike the derived activeToplevel.
    function touch(a) {
        if (!a) return;
        a = String(a).replace(/^0x/, "");
        if (root.mru[0] === a) return;
        root.mru = [a, ...root.mru.filter(x => x !== a)].slice(0, 200);
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindowv2") root.touch(event.data);
        }
    }

    // Seed once from Hyprland's own focus history (the shell may start after
    // you've been working); from then on focus events keep it current.
    Timer {
        interval: 1500; running: true
        onTriggered: {
            const seen = Hyprland.toplevels.values.filter(t => t.lastIpcObject && t.lastIpcObject.focusHistoryID !== undefined);
            seen.sort((a, b) => a.lastIpcObject.focusHistoryID - b.lastIpcObject.focusHistoryID);
            const seeded = seen.map(t => t.address);
            root.mru = [...root.mru, ...seeded.filter(a => root.mru.indexOf(a) < 0)];
        }
    }
    Component.onCompleted: Hyprland.refreshToplevels()

    function classOf(t) { return t && t.lastIpcObject ? (t.lastIpcObject["class"] || "") : ""; }
    function usable(t) {
        if (!t || !t.wayland || !t.workspace) return false;
        const ws = t.workspace;
        // Skip the shell's own and minimized windows; specials otherwise count.
        return !(ws.name === "special:minimized");
    }

    readonly property var list: {
        const all = Hyprland.toplevels.values.filter(usable);
        const rank = a => { const i = mru.indexOf(a); return i < 0 ? 1e6 : i; };
        let out = all.slice().sort((a, b) => rank(a.address) - rank(b.address));
        if (appOnly && appClass) out = out.filter(t => classOf(t) === appClass);
        if (workspaceOnly) {
            const ws = Hyprland.focusedWorkspace;
            out = out.filter(t => ws && t.workspace && t.workspace.id === ws.id);
        }
        return out;
    }
    readonly property var selected: list.length ? list[Math.max(0, Math.min(index, list.length - 1))] : null

    // ── Flow ─────────────────────────────────────────────────────────────
    function begin(dir, app, ws) {
        if (!active) {
            if (Hyprland.activeToplevel) touch(Hyprland.activeToplevel.address);
            Hyprland.refreshToplevels();
            appOnly = !!app;
            appClass = app ? classOf(Hyprland.activeToplevel) : "";
            workspaceOnly = !!ws;
            active = true;
            // Start on the previous window (or the last, going back).
            index = list.length > 1 ? (dir > 0 ? 1 : list.length - 1) : 0;
            reveal.restart();
            return;
        }
        step(dir);
    }
    function step(d) {
        if (!list.length) return;
        index = (index + d + list.length) % list.length;
    }
    function commit() {
        if (!active) return;
        const t = selected;
        const hadPanel = shown;
        finish();
        if (!t) return;
        // With the panel up, the island holds the keyboard; focusing now would
        // be undone the moment it lets go. Focus just after it has.
        if (hadPanel) { pendingFocus = t.address; focusLater.restart(); }
        else focus(t.address);
    }
    property string pendingFocus: ""
    function focus(address) { Hyprland.dispatch(`hl.dsp.focus({window = 'address:0x${address}'})`); }
    // Twice: the island's keyboard release isn't on a fixed clock, and focusing
    // the already-focused window again is harmless.
    Timer { id: focusLater; interval: 60; onTriggered: { if (root.pendingFocus) root.focus(root.pendingFocus); focusAgain.restart(); } }
    Timer { id: focusAgain; interval: 160; onTriggered: { if (root.pendingFocus) root.focus(root.pendingFocus); root.pendingFocus = ""; } }
    function cancel() { if (active) finish(); }
    function closeSelected() {
        const t = selected;
        if (t) Hyprland.dispatch(`hl.dsp.window.close({window = 'address:0x${t.address}'})`);
    }
    function toggleWorkspaceOnly() { workspaceOnly = !workspaceOnly; index = 0; }
    function finish() {
        reveal.stop();
        active = false;
        if (shown) {
            shown = false;
            if (Island.panel === "switcher") Island.close();
            Hyprland.dispatch("kuwai.capture_hold(false)");
        }
    }
    // The quick flick: no UI unless Alt is still held after 140 ms.
    Timer {
        id: reveal
        interval: 140
        onTriggered: {
            if (!root.active || root.list.length < 2) return;
            root.shown = true;
            Hyprland.dispatch("kuwai.capture_hold(true)");   // live previews aren't a screen share
            Island.open("switcher", "", "key");
        }
    }
    // If the island closes the panel (click outside, Esc), the switch is off.
    Connections {
        target: Island
        function onPanelChanged() { if (root.shown && Island.panel !== "switcher") root.finish(); }
    }
}
