pragma Singleton
// T3 Code's live work for the island: how many threads are running and how
// many wait for you (bin/rice-t3 reads T3's own state database read-only).
// Polled every 5 s while T3 Code's server is up; nothing when it isn't.
//
//   T3Code.running / waiting / items [{ status, title, provider }]
//   T3Code.focus()        bring the T3 Code window forward
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config

Singleton {
    id: root
    property bool alive: false
    property int running: 0
    property int waiting: 0
    property int finished: 0             // completed in the last 15 min (shown in the panel)
    property var items: []
    readonly property int total: running + waiting

    readonly property string bin: Quickshell.shellDir + "/../bin/rice-t3"
    Process {
        id: poll
        command: [root.bin]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.alive = !!d.alive;
                    root.running = d.running || 0;
                    root.waiting = d.waiting || 0;
                    root.finished = d.finished || 0;
                    // Only replace the list when it changed: an identical array
                    // still re-creates every delegate bound to it.
                    const next = d.items || [];
                    if (JSON.stringify(next) !== JSON.stringify(root.items)) root.items = next;
                } catch (e) {}
            }
        }
    }
    // A slower beat when T3 isn't running (it may start any time).
    Timer {
        interval: root.alive ? 5000 : 30000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!poll.running) poll.running = true
    }

    function focus() {
        // A Lua long string, as Notifs does: no quote/escape juggling.
        Hyprland.dispatch("hl.dsp.focus({window = [[class:^(com\\.t3tools\\.T3Code|t3code)$]]})");
    }
}
