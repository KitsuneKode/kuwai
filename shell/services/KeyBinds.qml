pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "keychord.mjs" as KC

Singleton {
    id: root

    property var entries: []
    property var live: []
    property string replaced: ""
    property bool loaded: false
    property bool failed: false
    property bool pinned: false
    property string error: ""
    property string editing: ""
    property var pending: null
    property var queue: []
    readonly property bool busy: writer.running
    readonly property string bin: Paths.bin + "/kuwai-keys"
    readonly property var editEntry: entries.find(e => e.aid === editing) || null
    readonly property var clash: pending && pending.canon && !pending.why ? KC.conflict(pending.canon, editing, entries, live) : null
    readonly property int changed: entries.filter(e => e.custom).length
    readonly property bool canSave: !!pending && !pending.why && !busy && (!clash || clash.kind === "kuwai")

    function load() {
        if (pinned) return;
        if (!ask.running) ask.running = true;
        if (!binds.running) binds.running = true;
        if (!replacedProc.running) replacedProc.running = true;
    }
    function run(args) {
        if (pinned || writer.running) return;
        writer.command = [bin].concat(args);
        writer.running = true;
    }
    function takenBy(e) {
        const c = e && e.def ? KC.conflict(KC.canon(e.def), e.aid, entries, live) : null;
        return c && c.kind !== "same" ? c : null;
    }
    function save() {
        const e = editEntry, p = pending, c = clash;
        if (!e || !canSave) return false;
        editing = "";
        pending = null;
        if (c && c.kind === "same") return true;
        run(["set", e.aid, p.keys, e.text].concat(c && c.entry ? [c.entry.aid, "", c.entry.text] : []));
        return true;
    }
    function reset(e) {
        const c = takenBy(e);
        if (c && c.kind === "kuwai" && c.entry) {
            queue = [["reset", e.aid]];
            run(["set", c.entry.aid, "", c.entry.text]);
        } else {
            run(["reset", e.aid]);
        }
    }
    function none(e) { run(["set", e.aid, "", e.text]); }
    function resetAll() { run(["reset-all"]); }

    Process {
        id: ask
        command: ["hyprctl", "repl", "return kuwai.palette(true)"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.pinned) return;
                try {
                    root.entries = JSON.parse(text).filter(e => e.kind === "bind" && e.aid);
                    root.failed = false;
                } catch (e) {
                    root.failed = true;
                }
                root.loaded = true;
            }
        }
    }
    Process {
        id: binds
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.pinned) return;
                try { root.live = JSON.parse(text); } catch (e) { root.live = []; }
            }
        }
    }
    Process {
        id: replacedProc
        command: ["hyprctl", "repl", "return kuwai.bind_conflicts()"]
        stdout: StdioCollector { onStreamFinished: if (!root.pinned) root.replaced = /←/.test(text) ? text.trim() : "" }
    }
    Process {
        id: writer
        onExited: code => {
            root.error = code === 0 ? "" : "Couldn't save that shortcut; nothing changed";
            const next = code === 0 && root.queue.length ? root.queue[0] : null;
            root.queue = [];
            if (next) Qt.callLater(() => root.run(next));
            else root.load();
        }
    }
}
