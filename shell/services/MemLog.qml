pragma Singleton
// Run-attributed natural-settle memory samples. See bin/rice-memlog.
// No forced GC, shared rotation temp, content, account identity or title capture.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root
    property int panelsOpened: 0
    property int centerOpened: 0
    property bool locked: false                 // set by shell.qml from Lock
    property int saverStarts: 0
    readonly property string runId: String(Date.now()) + "-" + Math.random().toString(36).slice(2)
    property int skipped: 0
    Process {
        id: append
        onExited: (code, status) => { if (code !== 0) console.warn("Memory sample could not be persisted"); }
    }
    function sample() {
        if (append.running) { root.skipped++; return; }
        append.command = [Paths.bin + "/rice-memlog", "--config", Quickshell.shellDir, "--run", root.runId,
                          "--render-loop", Quickshell.env("QSG_RENDER_LOOP") || "default", "--outputs", String(Quickshell.screens.length),
                          String(Notifs.items.length), String(panelsOpened), String(centerOpened), String(T3Code.items.length),
                          root.locked ? "1" : "0", String(saverStarts), String(root.skipped)];
        append.running = true;
    }
    Connections { target: Island; function onPanelChanged() { if (Island.panel !== "") root.panelsOpened++; } }
    Connections { target: Notifs; function onCenterOpenChanged() { if (Notifs.centerOpen) root.centerOpened++; } }
    Connections { target: Saver; function onShowingChanged() { if (Saver.showing) root.saverStarts++; } }
    Timer { interval: 600000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.sample() }
    Timer { interval: 60000; running: true; onTriggered: root.sample() }   // one early sample per start
}
