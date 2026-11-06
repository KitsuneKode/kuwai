pragma Singleton
// A slow memory diary, to find what grows over a long day (the shell sat at
// ~550 MB after 6 h, flat at idle, so held rather than leaking).
// Every 10 min one line to ~/.local/state/rice/memlog.tsv:
//   epoch  pss_anon_kb  notifications  panels_opened  center_opened  t3_items
// Read it with: column -t ~/.local/state/rice/memlog.tsv
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property int panelsOpened: 0
    property int centerOpened: 0
    readonly property string path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rice/memlog.tsv"

    FileView { id: smaps; path: "/proc/self/smaps_rollup"; blockLoading: false; printErrors: false }
    Process {
        id: append
        property string line: ""
        command: ["sh", "-c", 'printf "%s\\n" "$1" >> "$2"; tail -n 2000 "$2" > "$2.tmp" && mv "$2.tmp" "$2"', "memlog", line, root.path]
    }
    function sample() {
        smaps.reload();
        smaps.waitForJob();
        const m = /Pss_Anon:\s+(\d+)/.exec(smaps.text() || "");
        append.line = [Math.round(Date.now() / 1000), m ? m[1] : "?", Notifs.items.length, panelsOpened, centerOpened, T3Code.items.length].join("\t");
        if (!append.running) append.running = true;
    }
    Connections { target: Island; function onPanelChanged() { if (Island.panel !== "") root.panelsOpened++; } }
    Connections { target: Notifs; function onCenterOpenChanged() { if (Notifs.centerOpen) root.centerOpened++; } }
    Timer { interval: 600000; running: true; repeat: true; triggeredOnStart: false; onTriggered: root.sample() }
    Timer { interval: 60000; running: true; onTriggered: root.sample() }   // one early sample per start
}
