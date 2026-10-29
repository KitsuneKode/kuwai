// kittymux, read through its public contract (~/Projects/kittymux/docs/inbox.md):
//
//   inbox-snapshot.json    watched; rewritten atomically on every inbox change
//   kittymux pick --json   what needs you, running agents, recent conversations,
//                          each row carrying a validated `action`
//   kittymux act JSON      runs one of those actions (jump, reopen), the same
//                          door kittymux's own palette uses
//   kittymux inbox ack ID  marks an event read
//   agent-usage.json       provider quotas (what kittymux's usage view reads)
//
// Rows are refreshed when the inbox changes and every few seconds while the
// Agents tab is on screen; nothing polls while it's closed.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateDir: Quickshell.env("KITTYMUX_STATE")
        || ((Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/kittymux")
    readonly property string bin: home + "/.local/bin/kittymux"
    readonly property string iconDir: home + "/Projects/kittymux/assets/notify"

    property bool available: false
    property bool watching: false              // set while the Agents tab is visible

    property var inbox: ({ unread: 0, needs_you: 0, events: [] })
    property var rows: []                      // kittymux pick --json
    property var usage: []                     // [{ name, rows: [{ label, pct, reset }] }]

    // What needs you: unread inbox events, the ones blocking an agent first.
    readonly property var attention: {
        const rank = { "needs-you": 0, "warn": 1, "info": 2 };
        return (inbox.events || []).filter(e => e.status === "unread")
            .sort((a, b) => (rank[a.severity] ?? 3) - (rank[b.severity] ?? 3) || b.t - a.t);
    }
    readonly property int needsYou: inbox.needs_you || 0
    readonly property var running: rows.filter(r => r.kind === "running").map(parse)
    readonly property var recent: rows.filter(r => r.kind === "closed").slice(0, 6).map(parse)

    // Tab titles carry the agent's status glyph (✳ ◐ ◑ …): drop it.
    function clean(t) {
        return (t || "").replace(/^[^A-Za-z0-9~/.\u00C0-\u024F\u0400-\u04FF\u0900-\u097F]+\s*/, "");
    }

    // pick's text is laid out for a menu: "◐  claude  ◑ Title   ~/cwd   working".
    function parse(r) {
        const parts = r.text.split(/\s{2,}/).map(s => s.trim()).filter(s => s);
        const strip = clean;
        return {
            key: r.jkey || JSON.stringify(r.action),
            agent: r.agent,
            title: strip(parts[2]) || r.agent,
            where: parts[3] || "",
            status: parts.slice(4).join(" · "),
            working: r.tone === "active",
            action: r.action
        };
    }

    function icon(agent) {
        const name = (agent || "").toLowerCase().replace(/[^a-z0-9-]/g, "");
        return name ? "file://" + iconDir + "/" + name + ".png" : "";
    }

    // ── Actions ──────────────────────────────────────────────────────────
    function act(action) {
        run([bin, "act", JSON.stringify(action)]);
    }
    function jumpEvent(id) {
        run([bin, "inbox", "jump", id]);
    }
    function ack(id) {
        run([bin, "inbox", "ack", id]);
    }
    function ackAll() {
        run([bin, "inbox", "ack", "--all"]);
    }
    function openPanel() {
        run([bin, "panel", "toggle"]);
    }

    function run(cmd) {
        const p = runner.createObject(root, { command: cmd });
        p.running = true;
    }
    Component {
        id: runner
        Process {
            onExited: { destroy(); refresh.restart(); }
        }
    }

    // ── Sources ──────────────────────────────────────────────────────────
    Component.onCompleted: probe.running = true
    Process {
        id: probe
        command: ["test", "-x", root.bin]
        onExited: code => {
            root.available = code === 0;
            if (root.available) pick.running = true;
        }
    }

    FileView {
        path: root.available ? root.stateDir + "/inbox-snapshot.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); refresh.restart(); }
        onLoaded: {
            try { root.inbox = JSON.parse(text()); } catch (e) {}
        }
    }

    FileView {
        path: root.available ? root.stateDir + "/agent-usage.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let d = {};
            try { d = JSON.parse(text()); } catch (e) { return; }
            root.usage = (d.providers || []).map(p => ({
                name: p.name,
                rows: (p.rows || []).filter(r => typeof r.pct === "number")
                    .map(r => ({ label: r.label, pct: r.pct, reset: (r.reset || "").replace(/^resets in /, "") }))
            })).filter(p => p.rows.length);
        }
    }

    Timer { id: refresh; interval: 300; onTriggered: if (!pick.running) pick.running = true }
    Timer {
        interval: 4000
        repeat: true
        running: root.available && root.watching
        onTriggered: if (!pick.running) pick.running = true
    }
    Process {
        id: pick
        command: [root.bin, "pick", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.rows = JSON.parse(text); } catch (e) {}
            }
        }
    }
}
