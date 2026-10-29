// Brightness per monitor and night light, for the center's Display tab.
//
//   brightness   ~/Scripts/brightness.sh: `status` (JSON of every output)
//                and `set N --output NAME`; the controller coalesces
//                requests and handles DDC/CI for external monitors
//   night light  Hyprland's hyprsunset over hyprctl: `hyprsunset temperature`
//                reads/sets the colour temperature, `identity` turns it off
//
// Polled only while the tab is visible; a set is applied optimistically so
// the slider never waits on a slow DDC write.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool watching: false
    readonly property string script: Quickshell.env("HOME") + "/Scripts/brightness.sh"

    property var outputs: []                  // [{ name, value, internal, error }]
    property int temperature: 6500            // K; 6500 = off (identity)
    readonly property bool nightOn: temperature < 6400
    property int nightWarmth: 4200            // what turning it on restores

    function setBrightness(name, v) {
        v = Math.round(Math.max(1, Math.min(100, v)));
        outputs = outputs.map(o => o.name === name ? Object.assign({}, o, { value: v }) : o);
        pending[name] = v;
        sendLater.restart();
    }
    property var pending: ({})
    // Dragging fires many values; send the latest per output ~16 times a second.
    Timer {
        id: sendLater
        interval: 60
        onTriggered: {
            for (const name in root.pending)
                root.run([root.script, "set", String(root.pending[name]), "--output", name]);
            root.pending = {};
        }
    }

    function setTemperature(k) {
        k = Math.round(k / 100) * 100;
        temperature = k;
        if (k < 6400) nightWarmth = k;
        tempLater.restart();
    }
    Timer {
        id: tempLater
        interval: 60
        onTriggered: root.run(root.temperature >= 6400 ? ["hyprctl", "hyprsunset", "identity"]
                                                        : ["hyprctl", "hyprsunset", "temperature", String(root.temperature)])
    }
    function toggleNight() { setTemperature(nightOn ? 6500 : nightWarmth); }

    function run(cmd) {
        const p = runner.createObject(root, { command: cmd });
        p.running = true;
    }
    Component {
        id: runner
        Process { onExited: destroy() }
    }

    // ── Reading ──────────────────────────────────────────────────────────
    Timer {
        interval: 1500
        repeat: true
        triggeredOnStart: true
        running: root.watching
        onTriggered: {
            if (!status.running && !sendLater.running) status.running = true;
            if (!temp.running && !tempLater.running) temp.running = true;
        }
    }
    Process {
        id: status
        command: [root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }
                const outs = d.outputs || {};
                root.outputs = Object.keys(outs).sort((a, b) => /^eDP/.test(a) ? 1 : /^eDP/.test(b) ? -1 : a.localeCompare(b))
                    .map(n => ({
                        name: n,
                        value: root.pending[n] ?? (outs[n].pending ?? outs[n].value ?? 0),
                        internal: /^(eDP|LVDS|DSI)-/.test(n),
                        error: outs[n].error || ""
                    }));
            }
        }
    }
    Process {
        id: temp
        command: ["hyprctl", "hyprsunset", "temperature"]
        stdout: StdioCollector {
            onStreamFinished: {
                const k = parseInt(text);
                if (k > 0) {
                    root.temperature = k;
                    if (k < 6400) root.nightWarmth = k;
                }
            }
        }
    }
}
