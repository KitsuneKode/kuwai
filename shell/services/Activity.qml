pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "activity.mjs" as A

Singleton {
    id: root

    property int watchers: 0
    onWatchersChanged: sync()
    function watch() { watchers++; }
    function unwatch() {
        watchers = Math.max(0, watchers - 1);
        if (watchers === 0) clear();
    }

    property bool ready: false
    property bool failed: false
    onFailedChanged: sync()
    property double lastAt: 0
    property int crashes: 0
    property int cpus: 1
    property bool hold: false
    property string armedKey: ""
    property string armedAction: ""
    property var snap: A.empty()
    property var notes: ({})
    property var shown: []
    property var last: ({})
    readonly property ListModel rows: rowModel
    readonly property int count: rowModel.count
    readonly property string view: A.viewState({ failed: failed, ready: ready, count: rowModel.count })
    readonly property bool busy: ender.running

    ListModel { id: rowModel }

    function clear() {
        ready = false;
        failed = false;
        hold = false;
        armedKey = "";
        armedAction = "";
        snap = A.empty();
        notes = ({});
        shown = [];
        last = ({});
        rowModel.clear();
        disarm.stop();
    }

    function sync() { stream.running = watchers > 0 && !failed; }

    function retry() {
        failed = false;
        ready = false;
    }

    function fail() { failed = true; }

    function take(line) {
        const f = A.parseFrame(line);
        if (f) feed(f);
    }

    function show(raw) { take(JSON.stringify(raw)); }

    function feed(frame) {
        snap = A.step(snap, frame, { freeze: hold || armedKey !== "" });
        cpus = snap.cpus;
        ready = true;
        failed = false;
        lastAt = Date.now();
        crashes = 0;
        const arm = A.keepArmed({ key: armedKey, action: armedAction }, snap.keys);
        if (arm.key !== armedKey) { armedKey = arm.key; armedAction = arm.action; disarm.stop(); }
        const kept = {};
        for (const k of snap.keys) if (notes[k]) kept[k] = notes[k];
        if (Object.keys(kept).length !== Object.keys(notes).length) notes = kept;
        render();
    }

    function rowOf(key) {
        const r = snap.rows[key];
        return {
            key: key, unit: r.unit, appId: r.id, launcher: r.launcher, label: r.label, main: r.main,
            pid: r.pid, procs: r.procs, cpu: r.cpu, mem: r.mem, locked: r.protected,
            tone: A.cpuTone(r.cpu, snap.cpus), cpuText: A.cpuText(r.cpu), memText: A.memText(r.mem),
            detail: A.detail(r), note: notes[key] || ""
        };
    }

    function render() {
        const next = snap.keys;
        for (const op of A.diff(shown, next)) {
            if (op.op === "remove") rowModel.remove(op.at);
            else if (op.op === "move") rowModel.move(op.from, op.to, 1);
            else rowModel.insert(op.at, rowOf(op.key));
        }
        shown = next.slice();
        const seen = {};
        for (let i = 0; i < next.length; i++) {
            const row = rowOf(next[i]);
            const text = JSON.stringify(row);
            seen[next[i]] = text;
            if (last[next[i]] !== text) rowModel.set(i, row);
        }
        last = seen;
    }

    function press(key, action, name) {
        const r = A.press({ key: armedKey, action: armedAction }, key, action);
        armedKey = r.armed.key;
        armedAction = r.armed.action;
        if (armedKey !== "") disarm.restart(); else disarm.stop();
        if (r.fire) end(key, action === "force", name);
    }

    function end(key, force, name) {
        const r = snap.rows[key];
        if (!r || r.protected || ender.running) return;
        const next = Object.assign({}, notes);
        next[key] = force ? "Quitting…" : "Stopping…";
        notes = next;
        ender.key = key;
        ender.name = name || r.label;
        ender.command = [Paths.bin + "/kuwai-procs", "--end-unit", r.unit].concat(force ? ["--force"] : []);
        ender.running = true;
        render();
    }

    function ended(key, name, result) {
        const text = A.outcome(result, name);
        const next = Object.assign({}, notes);
        if (text) next[key] = text;
        else if (!snap.rows[key]) delete next[key];
        notes = next;
        render();
    }

    Timer { id: disarm; interval: Theme.undoMs; onTriggered: { root.armedKey = ""; root.armedAction = ""; } }

    Timer {
        interval: Theme.panelPollMs
        repeat: true
        running: root.watchers > 0 && !root.failed
        onTriggered: if (!root.ready || Date.now() - root.lastAt > Theme.panelPollMs) root.failed = true
    }

    Process {
        id: stream
        command: ["setpriv", "--pdeathsig", "KILL", "--", Paths.bin + "/kuwai-activity"]
        stdout: SplitParser { onRead: line => root.take(line) }
        onExited: (code, status) => {
            if (root.watchers === 0 || root.failed) return;
            if (status === 0 || ++root.crashes > 3) root.failed = true;
            else root.sync();
        }
    }

    Process {
        id: ender
        property string key: ""
        property string name: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) {}
                root.ended(ender.key, ender.name, r);
            }
        }
    }
}
