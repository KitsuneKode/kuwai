// kittymux, read through its public contract (~/Projects/kittymux/docs/inbox.md):
//
//   inbox-snapshot.json    watched; rewritten atomically on every inbox change
//   kittymux pick --json   what needs you, running agents, recent conversations,
//                          each row carrying a validated `action`
//   kittymux act JSON      runs one of those actions (jump, reopen), the same
//                          door kittymux's own palette uses
//   kittymux inbox ack ID  marks an event read
//   agent-usage.json       provider quotas (what kittymux's usage view reads)
//   agents.json            watched; the live agent feed (version 1): every running
//                          agent with its state, brand, question, progress and a
//                          jump action. With it, nothing parses menu text and the
//                          island needs no poll; without it (older kittymux) the
//                          20 s `pick` look below is the fallback.
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
    property var feed: null                    // agents.json, when this kittymux publishes it
    readonly property bool live: !!feed && feed.version === 1 && Array.isArray(feed.agents)
    property bool loaded: false                // first pick has answered
    property var usage: []                     // [{ name, rows: [{ label, pct, reset }] }]

    // What needs you: unread inbox events, the ones blocking an agent first.
    readonly property var attention: {
        const rank = { "needs-you": 0, "warn": 1, "info": 2 };
        return (inbox.events || []).filter(e => e.status === "unread")
            .sort((a, b) => (rank[a.severity] ?? 3) - (rank[b.severity] ?? 3) || b.t - a.t);
    }
    readonly property int needsYou: inbox.needs_you || 0
    readonly property var running: live ? feed.agents.map(fromFeed) : rows.filter(r => r.kind === "running").map(parse)
    readonly property var recent: rows.filter(r => r.kind === "closed").slice(0, 6).map(parse)

    // Tab titles carry the agent's status glyph (✳ ◐ ◑ …): drop it.
    function clean(t) {
        return (t || "").replace(/^[^A-Za-z0-9~/.\u00C0-\u024F\u0400-\u04FF\u0900-\u097F]+\s*/, "");
    }

    // One agents.json row in the shape the island and the Agents tab already use, plus the live fields.
    function fromFeed(a) {
        const words = { working: "working", waiting: "needs you", done: "done", idle: "idle",
                        limited: "hit a limit", error: "error" };
        let status = words[a.state] || a.state || "";
        if (a.state === "error" && a.error) status = a.error;
        if (a.state === "limited" && a.limit_reset) {
            const mins = Math.max(0, Math.round((a.limit_reset - Date.now() / 1000) / 60));
            const h = Math.floor(mins / 60), m = mins % 60;
            status += " · resets in " + (h ? h + "h" + (m ? " " + m + "m" : "") : m + "m");
        }
        return {
            key: a.key,
            agent: a.agent,
            brand: a.brand || "",
            title: clean(a.title) || a.tab_title || a.agent,
            where: a.cwd || "",
            status: status,
            state: a.state,
            question: a.question || "",
            progress: a.progress,
            working: a.state === "working",
            action: a.action
        };
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

    // The real brand mark (shell/assets/brands, tinted copies of kittymux's
    // assets/icons), else kittymux's own notification art.
    readonly property var brands: ({
        claude: "claude", "claude-code": "claudecode", codex: "openai", openai: "openai", cursor: "cursor",
        "cursor-agent": "cursor", gemini: "googlegemini", agy: "antigravity", antigravity: "antigravity",
        grok: "grok", devin: "devin", opencode: "opencode", amp: "amp", goose: "goose", kimi: "kimi",
        qwen: "qwen", vibe: "mistralvibe", junie: "junie", kilo: "kilo", auggie: "auggie", droid: "factorydroid",
        kittymux: "kittymux"
    })
    readonly property string brandDir: Qt.resolvedUrl("../assets/brands")
    function brand(agent) {
        const name = (agent || "").toLowerCase().replace(/[^a-z0-9-]/g, "");
        return brands[name] ? brandDir + "/" + brands[name] + ".svg" : "";
    }
    function icon(agent) {
        const name = (agent || "").toLowerCase().replace(/[^a-z0-9-]/g, "");
        return brand(name) || (name ? "file://" + iconDir + "/" + name + ".png" : "");
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
        path: root.available ? root.stateDir + "/agents.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.feed = JSON.parse(text()); root.loaded = true; } catch (e) {}
        }
        onLoadFailed: root.feed = null           // no file: an older kittymux, so pick stays the source
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
    // The island shows who is working: a look every 20 s (the inbox file
    // already says the moment one needs you or finishes).
    // With agents.json the feed is live and this look is not needed.
    Timer { interval: 20000; repeat: true; triggeredOnStart: true; running: root.available && !root.watching && !root.live; onTriggered: if (!pick.running) pick.running = true }
    readonly property var working: running.filter(r => r.working)
    Timer {
        // While the Agents tab shows: the running list is live from agents.json, so only the
        // recent-conversations list (pick's `closed` rows) needs a look, and not as often.
        interval: root.live ? 30000 : 4000
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
                root.loaded = true;
            }
        }
    }
}
