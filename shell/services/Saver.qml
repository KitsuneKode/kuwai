pragma Singleton

// The screensaver's state, for whoever shouldn't waste work under it (the
// live wallpaper pauses: nobody can see it, and the same file would be
// decoded twice). Also the lock and the screens being off (modules/lock,
// services/Idle): nobody is looking, so device cards and ambient moments
// keep quiet, and what changed is not replayed when you come back.
// (No braces before the pragma: Quickshell's scanner stops.)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root
    property bool showing: false
    property bool locked: false
    property bool screensOff: false
    property var outputOff: ({})
    // Nobody is looking now, or you came back a moment ago: monitors waking
    // from power-off come back as new outputs (their audio too), Bluetooth
    // reconnects; none of that is news.
    readonly property bool away: locked || screensOff || settling.running
    onLockedChanged: { if (!locked) settling.restart(); probeDpms(); }
    onScreensOffChanged: if (!screensOff) settling.restart()
    Timer { id: settling; interval: 8000 }

    function isOutputOff(name) {
        return screensOff || !!(name && outputOff && outputOff[name]);
    }
    function applyMonitors(text) {
        let list = null;
        try { list = JSON.parse(text); } catch (e) { return false; }
        if (!Array.isArray(list) || !list.length) return false;
        const off = {};
        let anyOn = false;
        for (let i = 0; i < list.length; i++) {
            const m = list[i];
            if (!m || !m.name) continue;
            if (m.dpmsStatus === false || !!m.disabled) off[m.name] = true;
            else anyOn = true;
        }
        root.outputOff = off;
        root.screensOff = !anyOn;
        return true;
    }
    function handleHyprEvent(name, data) {
        if (name === "dpms" || name === "dpmsv2") {
            const parts = String(data || "").split(",");
            if (parts.length >= 2) {
                const out = parts[0].trim();
                const on = parts[1].trim();
                if (out && (on === "0" || on === "false" || on === "1" || on === "true")) {
                    const next = Object.assign({}, root.outputOff || {});
                    if (on === "0" || on === "false") next[out] = true;
                    else delete next[out];
                    root.outputOff = next;
                }
            }
            probeDpms();
        } else if (name === "monitoradded" || name === "monitoraddedv2" || name === "monitorremoved" || name === "monitorremovedv2" || name === "configreloaded") {
            probeDpms();
        }
    }
    function probeDpms() {
        if (dpmsProbe.running) { dpmsProbe.again = true; return; }
        dpmsProbe.running = true;
    }
    Process {
        id: dpmsProbe
        property bool again: false
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.applyMonitors(text)
        }
        onExited: {
            if (again) { again = false; running = true; }
        }
    }
    Connections {
        target: typeof Hyprland !== "undefined" ? Hyprland : null
        function onRawEvent(event) { root.handleHyprEvent(event.name, event.data); }
    }
    Component.onCompleted: probeDpms()
}
