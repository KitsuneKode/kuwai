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
    // The accurate preset holds Night Shift off; the switch says so instead.
    function toggleNight() { if (!nightHeld) setTemperature(nightOn ? 6500 : nightWarmth); }
    readonly property bool nightHeld: preset === "accurate"

    // ── Display presets (kuwai.display in hypr/kuwai/display.lua) ────────
    // choice = what you picked; auto = what kuwai put on top of everyday
    // (an open colour app → accurate, unplugged → battery); preset = in effect.
    readonly property var presets: [
        { id: "everyday", label: "Everyday",  about: "Configured refresh rates · Night Shift on its schedule" },
        { id: "accurate", label: "Accurate",  about: "Night Shift held off · strict colour pipeline, for judging colour" },
        { id: "movie",    label: "Movie",     about: "Monitor at 120 Hz: 24, 30 and 60 fps play without judder" },
        { id: "gaming",   label: "Game",      about: "Game look: no blur, shadows or animation · tearing allowed" },
        { id: "battery",  label: "Battery",   about: "Built-in screen at 60 Hz" }
    ]
    property string choice: "everyday"
    property string auto: ""
    property string autoWhy: ""
    readonly property string preset: choice === "everyday" && auto !== "" ? auto : choice
    function presetInfo(id) { return presets.find(p => p.id === id) || presets[0]; }
    function setPreset(id) {
        if (!presets.some(p => p.id === id)) return;
        choice = id; auto = ""; autoWhy = "";            // optimistic; the state file confirms
        run(["hyprctl", "eval", `kuwai.display("${id}")`]);
    }
    // Scrolling through presets: the label follows at once, but only the one
    // you stop on is applied (each apply is a reload, a rate change blanks).
    function cyclePreset(step) {
        const i = presets.findIndex(p => p.id === preset);
        choice = presets[(i + step + presets.length) % presets.length].id;
        auto = ""; autoWhy = "";
        commitLater.restart();
    }
    Timer {
        id: commitLater
        interval: 700
        onTriggered: root.setPreset(root.choice)
    }
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/kuwai/state"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const t = text();
            const get = k => { const m = t.match(new RegExp("^" + k + "=(\\S+)", "m")); return m ? m[1] : ""; };
            root.choice = get("display") || "everyday";
            root.auto = get("display_auto");
            const why = t.match(/^display_why=(.*)$/m);
            root.autoWhy = why ? why[1] : "";
        }
    }

    // What each screen is actually doing, read back from Hyprland (polled
    // with brightness while the Controls tab is open): { name: { hz, depth, hdr, vrr } }
    property var screens: ({})
    Process {
        id: mons
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }
                const s = {};
                for (const m of d)
                    s[m.name] = {
                        hz: Math.round(m.refreshRate),
                        depth: /2101010|16161616/.test(m.currentFormat || "") ? 10 : 8,
                        hdr: /hdr/i.test(m.colorManagementPreset || ""),
                        vrr: !!m.vrr
                    };
                root.screens = s;
            }
        }
    }

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
            if (!mons.running) mons.running = true;
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
