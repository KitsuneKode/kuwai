pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    property var report: null
    property bool loaded: false
    property bool failed: false
    property bool pinned: false
    property int watchers: 0
    property bool restartNeeded: false
    property bool restartWaiting: false
    property string note: ""
    property bool noteBad: false
    property var pendingSet: null
    readonly property bool busy: setter.running || restarter.running
    readonly property string bin: Paths.bin + "/kuwai-dictation"

    function open() {
        watchers += 1;
        load();
    }
    function close() {
        watchers = Math.max(0, watchers - 1);
        if (watchers === 0) note = "";
    }
    function load() {
        if (pinned || reader.running) return;
        reader.running = true;
    }
    function choose(name, value) {
        if (pinned || setter.running || !report || !report.voxtype || !report.voxtype.config) return;
        const cfg = Object.assign({}, report.voxtype.config);
        pendingSet = { name: name, was: cfg[name] };
        cfg[name] = value;
        report = Object.assign({}, report, { voxtype: Object.assign({}, report.voxtype, { config: cfg }) });
        setter.command = [bin, "set", name, typeof value === "boolean" ? (value ? "on" : "off") : String(value)];
        setter.running = true;
    }
    function restart() {
        if (pinned || restarter.running) return;
        restarter.running = true;
    }
    function settle(o) {
        if (o && o.restarted) {
            restartNeeded = false;
            restartWaiting = false;
            note = "Dictation restarted with these settings";
            noteBad = false;
            reread.restart();
        } else if (o && o.state === "stopped") {
            restartNeeded = false;
            restartWaiting = false;
            note = "Dictation isn't running; these settings apply when it starts";
            noteBad = false;
        } else if (o && o.state && o.state !== "idle") {
            restartWaiting = true;
            note = "";
        } else {
            restartWaiting = false;
            note = "Couldn't restart dictation; try again in a moment";
            noteBad = true;
        }
    }

    Connections {
        target: Activities
        function onVoxStateChanged() {
            if (Activities.voxState !== "idle") return;
            if (root.restartWaiting) root.restart();
            else if (root.watchers > 0) root.load();
        }
    }
    Timer { id: reread; interval: 1500; onTriggered: if (root.watchers > 0) root.load() }

    Process {
        id: reader
        command: [root.bin, "read"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.pinned) return;
                try {
                    const o = JSON.parse(text);
                    root.report = o && o.voxtype && o.shuush ? o : null;
                } catch (e) {
                    root.report = null;
                }
                root.failed = root.report === null;
                root.loaded = true;
            }
        }
    }
    Process {
        id: setter
        stdout: StdioCollector {
            onStreamFinished: {
                let ok = false;
                try { ok = JSON.parse(text).ok === true; } catch (e) { ok = false; }
                const p = root.pendingSet;
                root.pendingSet = null;
                if (ok) {
                    root.restartNeeded = true;
                    root.note = "";
                    return;
                }
                if (p && root.report && root.report.voxtype && root.report.voxtype.config) {
                    const cfg = Object.assign({}, root.report.voxtype.config);
                    cfg[p.name] = p.was;
                    root.report = Object.assign({}, root.report, { voxtype: Object.assign({}, root.report.voxtype, { config: cfg }) });
                }
                root.note = "Couldn't change that; nothing changed";
                root.noteBad = true;
            }
        }
    }
    Process {
        id: restarter
        command: [root.bin, "restart"]
        stdout: StdioCollector {
            onStreamFinished: {
                let o = null;
                try { o = JSON.parse(text); } catch (e) { o = null; }
                root.settle(o);
            }
        }
    }
}
