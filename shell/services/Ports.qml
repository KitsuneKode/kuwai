pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "ports.mjs" as P
import "links.mjs" as Links

Singleton {
    id: root

    property int watchers: 0
    property bool ready: false
    property bool failed: false
    property bool staged: false
    property bool hold: false
    property string sortKey: "port"
    property int sortDir: 1
    property string armedKey: ""
    property string armedAction: ""
    property var snap: P.empty()
    property var latestRows: []
    property var notes: ({})
    property var shown: []
    property var last: ({})
    readonly property ListModel rows: rowModel
    readonly property int count: rowModel.count
    readonly property string phase: P.phase({ failed: failed, ready: ready, count: rowModel.count })
    readonly property bool busy: ender.running

    ListModel { id: rowModel }

    function watch() { watchers++; }
    function unwatch() {
        watchers = Math.max(0, watchers - 1);
        if (watchers === 0) clear();
    }

    function clear() {
        ready = false;
        failed = false;
        staged = false;
        hold = false;
        armedKey = "";
        armedAction = "";
        snap = P.empty();
        latestRows = [];
        notes = ({});
        shown = [];
        last = ({});
        rowModel.clear();
        disarm.stop();
    }

    function retry() {
        failed = false;
        ready = false;
        staged = false;
        if (!poll.running) poll.running = true;
    }

    function chooseSort(key) {
        if (sortKey === key) sortDir = -sortDir;
        else { sortKey = key; sortDir = 1; }
        snap = P.resort(snap);
        feedRows(latestRows);
    }

    function feedText(out) {
        const rows = P.parseRows(out);
        if (rows === null) failed = true;
        else feedRows(rows);
    }

    function show(raw) { staged = true; feedText(JSON.stringify(raw)); }

    function feedRows(rows) {
        latestRows = rows;
        snap = P.step(snap, rows, { sortKey: sortKey, sortDir: sortDir, freeze: hold || armedKey !== "" });
        ready = true;
        failed = false;
        const arm = P.keepArmed({ key: armedKey, action: armedAction }, snap.keys);
        if (arm.key !== armedKey) {
            armedKey = arm.key;
            armedAction = arm.action;
            disarm.stop();
        }
        const kept = {};
        for (const k of snap.keys) if (notes[k]) kept[k] = notes[k];
        if (Object.keys(kept).length !== Object.keys(notes).length) notes = kept;
        render();
    }

    function rowOf(key) {
        const r = snap.rows[key];
        return {
            key: key, port: r.port, host: r.host, proc: r.proc, what: r.what, project: r.project,
            title: r.title, pid: r.pid, start: r.start, age: r.age, agent: r.agent, parentApp: r.parentApp,
            memBytes: r.memBytes, cpu: r.cpu, local: r.local, monogram: r.monogram, scope: r.scope,
            memText: r.memText, sub: r.sub, openable: r.openable, note: notes[key] || ""
        };
    }

    function render() {
        const next = snap.keys;
        for (const op of P.diff(shown, next)) {
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
        const r = P.press({ key: armedKey, action: armedAction }, key, action);
        armedKey = r.armed.key;
        armedAction = r.armed.action;
        if (armedKey !== "") disarm.restart(); else disarm.stop();
        if (r.fire) {
            const row = snap.rows[key];
            if (row) stop(row.pid, row.start, action === "force", name);
        }
    }

    function stop(pid, start, force, name) {
        pid = Math.trunc(Number(pid));
        start = Math.trunc(Number(start));
        if (!(pid > 0) || !(start >= 0) || ender.running) return;
        const key = pid + ":" + start;
        const row = snap.rows[key];
        const next = Object.assign({}, notes);
        next[key] = force ? "Quitting…" : "Stopping…";
        notes = next;
        ender.key = key;
        ender.name = name || (row ? row.title : "server");
        ender.command = [Paths.bin + "/kuwai-procs", "--end", String(pid), "--start", String(start)].concat(force ? ["--force"] : []);
        ender.running = true;
        render();
    }

    function ended(key, name, result) {
        const text = P.outcome(result, name);
        const next = Object.assign({}, notes);
        if (text) next[key] = text;
        else if (!snap.rows[key]) delete next[key];
        else delete next[key];
        notes = next;
        render();
    }

    function openUrl(port) {
        const url = "http://localhost:" + Math.trunc(Number(port));
        if (Links.safeLink(url)) Apps.open(url);
    }

    Timer { id: disarm; interval: Theme.undoMs; onTriggered: { root.armedKey = ""; root.armedAction = ""; } }

    Timer {
        interval: Theme.panelPollMs
        repeat: true
        triggeredOnStart: true
        running: root.watchers > 0 && !root.failed && !root.staged
        onTriggered: if (!poll.running) poll.running = true
    }

    Process {
        id: poll
        command: [Paths.bin + "/kuwai-ports"]
        stdout: StdioCollector { id: collected }
        onExited: (code, status) => {
            if (root.watchers === 0 || root.staged) return;
            if (code !== 0) root.failed = true;
            else root.feedText(collected.text);
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
