// Brightness per monitor and night light, for the center's Display tab.
//
//   brightness   bin/rice-brightness: `status` (JSON of every output)
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
import Quickshell.Hyprland
import qs.config

Singleton {
    id: root

    property bool watching: false
    readonly property string script: Paths.bin + "/rice-brightness"

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
        // Off: 6500 K first (identity alone keeps reporting the old warm value).
        onTriggered: root.run(root.temperature >= 6400 ? ["sh", "-c", "hyprctl hyprsunset temperature 6500; hyprctl hyprsunset identity"]
                                                        : ["hyprctl", "hyprsunset", "temperature", String(root.temperature)])
    }
    // The accurate preset holds Night Shift off; the switch says so instead.
    function toggleNight() { if (!nightHeld) setTemperature(nightOn ? 6500 : nightWarmth); }
    readonly property bool nightHeld: preset === "accurate"

    // ── Display presets (kuwai.display in hypr/kuwai/display.lua) ────────
    // choice = what you picked; auto = what kuwai put on top of everyday
    // (an open colour app → accurate, unplugged → battery); preset = in effect.
    readonly property var presets: [
        { id: "everyday", label: "Everyday",  about: "Each screen at its configured refresh rate" },
        { id: "accurate", label: "Accurate",  about: "Night Shift held off · strict colour pipeline, for judging colour" },
        { id: "movie",    label: "Movie",     about: "Monitor at 120 Hz: 24, 30 and 60 fps play without judder" },
        { id: "gaming",   label: "Game",      about: "Game look: no blur, shadows or animation · tearing allowed" },
        { id: "battery",  label: "Battery",   about: "Built-in screen at 60 Hz" }
    ]
    property string choice: "everyday"
    property string auto: ""
    property string autoWhy: ""
    readonly property string preset: choice === "everyday" && auto !== "" ? auto : choice
    // A change shows in the notch for a moment (not the one read at start).
    property bool presetKnown: false
    onPresetChanged: {
        if (!presetKnown) return;
        const automatic = auto !== "" && choice === "everyday";
        Moments.show({ kind: "display", glyph: "\u{f0379}", label: "Display",
                       value: presetInfo(preset).label + (automatic ? " · auto" : ""), ring: -1, tone: Theme.cyan }, 1800);
    }
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
            root.presetKnown = true;
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

    // ── HDR notice ───────────────────────────────────────────────────────
    // Hyprland switches a screen to HDR by itself when an HDR video or game
    // goes fullscreen (render.cm_auto_hdr) and says nothing about it. So just
    // after a fullscreen change, look three times (the switch lands a moment
    // later): a screen newly in HDR gets a moment in the notch.
    property var hdrOn: ({})                  // screen name → true while in HDR
    property var hdrWire: ({})                // rice-hdr's last reading: name → { hdr, eotf, maxNits, colorspace }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "fullscreen") return;
            root.hdrLooks = 0;
            hdrLook.restart();
        }
    }
    property int hdrLooks: 0
    Timer {
        id: hdrLook
        interval: 1200
        repeat: true
        onTriggered: {
            if (++root.hdrLooks >= 3) stop();
            if (!hdrProbe.running) hdrProbe.running = true;
        }
    }
    Process {
        id: hdrProbe
        // The preset's name, and the signal really on the wire (rice-hdr reads
        // each connector's HDR infoframe): an automatic switch sends PQ while
        // the preset still says "srgb", which is when the label matters most.
        command: ["sh", "-c", 'hyprctl -j monitors; echo; echo "#wire"; "$1" 2>/dev/null || echo "{}"', "hdr", Paths.bin + "/rice-hdr"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d, wire = {};
                const cut = text.indexOf("#wire");
                try { d = JSON.parse(cut >= 0 ? text.slice(0, cut) : text); } catch (e) { return; }
                try { wire = JSON.parse(cut >= 0 ? text.slice(cut + 5) : "{}") || {}; } catch (e) { wire = {}; }
                root.hdrWire = wire;
                const on = {};
                for (const m of d) {
                    const w = wire[m.name];
                    if (!(w && w.hdr) && !/hdr/i.test(m.colorManagementPreset || "")) continue;
                    on[m.name] = true;
                    if (!root.hdrOn[m.name]) {
                        // The resting notch is under a fullscreen window, so
                        // the line grows out of it (the same card as a device)
                        // and IslandBar lifts that card onto the overlay.
                        const fs = !!(Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen);
                        if (fs)
                            Moments.showCard({ key: "hdr:" + m.name, glyph: "\u{f0379}", title: "HDR",
                                               state: (w && w.hdr ? w.eotf + (w.maxNits ? " · " + w.maxNits + " nits" : "") + " · " : "") + (m.model || m.name), tone: Theme.yellow, battery: -1, quiet: true }, 2200);
                        else
                            Moments.show({ kind: "hdr", glyph: "\u{f0379}", label: "HDR",
                                           value: (w && w.hdr ? w.eotf + " · " : "") + (m.model || m.name), ring: -1, tone: Theme.yellow }, 2200);
                    }
                }
                root.hdrOn = on;
            }
        }
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
