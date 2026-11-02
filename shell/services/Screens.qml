// Which monitor is focused, reliably. Quickshell's Hyprland.focusedMonitor
// stays null after a (re)start until focus next changes, so surfaces that
// asked it fell back to the first screen (toasts showed up on the laptop
// while you were on the external monitor). Ask Hyprland once at startup,
// then follow its focus events.
//
// Quickshell's own focusedMonitor also went stale under Hyprland 0.57 (panels
// opened on the laptop while you were on the Acer), so the monitor is
// followed here from Hyprland's raw events: focusedmon(v2), and the monitor
// of each newly focused window (activewindowv2). Anything opened from the
// keyboard asks Hyprland directly first (refresh(), ~7 ms).
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property string probed: ""
    property string tracked: ""
    Connections {
        target: typeof Hyprland !== "undefined" ? Hyprland : null
        function onRawEvent(event) {
            if (event.name === "focusedmon" || event.name === "focusedmonv2") {
                const n = String(event.data).split(",")[0];
                if (n) root.tracked = n;
            } else if (event.name === "activewindowv2") {
                const a = String(event.data).replace(/^0x/, "");
                const t = a ? Hyprland.toplevels.values.find(x => x.address === a) : null;
                const m = t && t.workspace && t.workspace.monitor ? t.workspace.monitor : null;
                if (m && m.name) root.tracked = m.name;
            }
        }
    }
    // Ask Hyprland which monitor has focus now, then call back with its name
    // (with the best guess if hyprctl doesn't answer within 150 ms).
    property var waiting: []
    function refresh(cb) {
        if (cb) waiting.push(cb);
        if (!probe.running) probe.running = true;
        giveUp.restart();
    }
    function flush() {
        giveUp.stop();
        const w = waiting; waiting = [];
        for (const f of w) { try { f(focusedName); } catch (e) {} }
    }
    Timer { id: giveUp; interval: 150; onTriggered: root.flush() }
    // (Guarded: while a hot reload tears the old copy down, Hyprland can be
    // briefly unavailable.)
    readonly property string focusedName: {
        if (tracked) return tracked;
        const m = typeof Hyprland !== "undefined" && Hyprland ? Hyprland.focusedMonitor : null;
        if (m && m.name) return m.name;
        if (probed) return probed;
        const first = Quickshell.screens.length ? Quickshell.screens[0] : null;
        return first && first.name ? first.name : "";
    }
    readonly property var focused: Quickshell.screens.find(s => s.name === focusedName) || Quickshell.screens[0]

    function screenNamed(name) {
        return Quickshell.screens.find(s => s.name === name) || focused;
    }

    Component.onCompleted: probe.running = true
    Process {
        id: probe
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const m = JSON.parse(text).find(x => x.focused);
                    if (m) { root.probed = m.name; root.tracked = m.name; }
                } catch (e) {}
                root.flush();
            }
        }
    }
}
