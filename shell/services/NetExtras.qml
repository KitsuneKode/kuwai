pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "netExtras.mjs" as N

Singleton {
    id: root

    property int watchers: 0
    function watch(on) { watchers = Math.max(0, watchers + (on ? 1 : -1)); if (on) refresh(); }

    property var vpns: []
    property var printers: []
    property var jobs: []
    property string backend: ""
    property string iwdDevice: ""
    property bool iwdPowered: false
    property string iwdNetwork: ""

    property bool pinned: false
    function refresh() {
        if (pinned) return;
        if (!nm.running) nm.running = true;
        if (!cups.running) cups.running = true;
        if (!probe.running) probe.running = true;
    }
    Timer { interval: 5000; repeat: true; running: root.watchers > 0; onTriggered: root.refresh() }

    Process {
        id: nm
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,ACTIVE", "connection", "show"]
        stdout: StdioCollector { onStreamFinished: root.vpns = N.vpns(text) }
    }
    function setVpn(uuid, up) {
        Quickshell.execDetached(["nmcli", "connection", up ? "up" : "down", "uuid", uuid]);
        later.restart();
    }

    Process {
        id: cups
        command: ["sh", "-c", "command -v lpstat >/dev/null || exit 0; lpstat -p -d 2>/dev/null; echo '--jobs--'; lpstat -o 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("--jobs--");
                root.printers = N.printers(parts[0] || "");
                root.jobs = N.jobs(parts[1] || "");
            }
        }
    }
    function setDefaultPrinter(name) { Quickshell.execDetached(["lpoptions", "-d", name]); later.restart(); }
    function cancelJob(id) { Quickshell.execDetached(["cancel", id]); later.restart(); }

    Process {
        id: probe
        command: ["sh", "-c", `
            if busctl --system --no-pager status org.freedesktop.NetworkManager >/dev/null 2>&1; then echo nm; exit 0; fi
            command -v iwctl >/dev/null || { echo none; exit 0; }
            dev=$(iwctl device list 2>/dev/null | sed 's/\\x1b\\[[0-9;]*m//g' | awk '$3 == "station" || $4 == "station" { print $1; exit }')
            [ -n "$dev" ] || { echo none; exit 0; }
            echo "iwd $dev"
            iwctl device "$dev" show 2>/dev/null | sed 's/\\x1b\\[[0-9;]*m//g' | awk '/Powered/ { print "powered " $NF }'
            iwctl station "$dev" show 2>/dev/null | sed 's/\\x1b\\[[0-9;]*m//g'`]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const first = (lines[0] || "").trim().split(/\s+/);
                root.backend = first[0] || "";
                root.iwdDevice = first[0] === "iwd" ? (first[1] || "") : "";
                const p = text.match(/^powered (\S+)/m);
                root.iwdPowered = !!p && p[1] === "on";
                root.iwdNetwork = N.iwdStation(text).network;
            }
        }
    }
    function setIwdPower(on) {
        if (!iwdDevice) return;
        Quickshell.execDetached(["iwctl", "device", iwdDevice, "set-property", "Powered", on ? "on" : "off"]);
        later.restart();
    }
    function iwdPicker() {
        Apps.run(["sh", "-c", 'p=iwctl; command -v impala >/dev/null && p=impala; for t in kitty foot alacritty ghostty wezterm; do command -v "$t" >/dev/null && exec "$t" -e "$p"; done']);
    }
    Timer { id: later; interval: 900; onTriggered: root.refresh() }
}
