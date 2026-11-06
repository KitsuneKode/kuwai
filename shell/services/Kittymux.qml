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
//   tabs.json              watched; one kitty OS window per entry and its tabs
//                          (version 1). The tabs column reads `tabs`. Until the
//                          file exists, `tabs` is the running agents.
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
    // Override with KITTYMUX_ROOT when kittymux isn't under ~/Projects/kittymux.
    readonly property string muxRoot: Quickshell.env("KITTYMUX_ROOT") || (home + "/Projects/kittymux")
    readonly property string iconDir: muxRoot + "/assets/notify"

    property bool available: false
    property bool watching: false              // set while the Agents tab is visible

    property var inbox: ({ unread: 0, needs_you: 0, events: [] })
    property var rows: []                      // kittymux pick --json
    property var feed: null                    // agents.json, when this kittymux publishes it
    readonly property bool live: !!feed && feed.version === 1 && Array.isArray(feed.agents)
    property var tabsDoc: null                 // tabs.json, when this kittymux publishes it
    readonly property bool tabsLive: !!tabsDoc && tabsDoc.version === 1 && Array.isArray(tabsDoc.windows)
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
    // Closed conversations, worth reopening: a title that's just the last
    // shell command (rm -f …, cc auth login) reads as the agent's session,
    // repeats fold into one, four at most. (It listed raw commands.)
    readonly property var recent: {
        const seen = {}, out = [];
        for (const r of rows.filter(x => x.kind === "closed").map(parse)) {
            if (looksLikeCommand(r.title)) r.title = agentLabel(r.agent) + " session";
            const k = r.agent + "|" + r.title + "|" + r.where;
            if (seen[k]) continue;
            seen[k] = true;
            out.push(r);
            if (out.length >= 4) break;
        }
        return out;
    }
    function looksLikeCommand(t) {
        const x = String(t || "").trim();
        return x === "" || /^(rm|cd|ls|git|sudo|cat|mv|cp|kill|pkill|cc|cdx|npm|bun|pnpm|yarn|make|python3?|node|ssh|exit|clear|vim|nvim)\b/.test(x)
            || /(^|\s)(-{1,2}[a-z]|~\/|\/[a-z])/i.test(x);
    }
    function agentLabel(a) {
        const n = String(a || "").replace(/-agent$/, "");
        return ({ claude: "Claude", codex: "Codex", cursor: "Cursor", agy: "Antigravity", gemini: "Gemini", opencode: "OpenCode" })[n] || (n ? n.charAt(0).toUpperCase() + n.slice(1) : "Agent");
    }

    // OSC 9;4: a fraction from agents.json, or {state, pct} from tabs.json (pct is 0–100).
    function progressPct(p) {
        if (p == null) return null;
        if (typeof p === "number") return Math.max(0, Math.min(100, Math.round(p <= 1 ? p * 100 : p)));
        if (typeof p === "object" && p.state === "set" && typeof p.pct === "number")
            return Math.max(0, Math.min(100, Math.round(p.pct)));
        return null;
    }
    function ageFrom(since) {
        if (!since) return "";
        const s = Math.max(0, Date.now() / 1000 - since);
        if (s < 45) return "<1m";
        const m = Math.round(s / 60);
        if (m < 60) return m + "m";
        const h = Math.floor(m / 60);
        return h + "h";
    }
    function placeOf(t) {
        const sub = (t.subtitle || "").trim();
        if (sub) return sub;
        const bits = [t.project, t.branch].filter(s => s);
        if (bits.length) return bits.join(" · ");
        return t.cwd || "";
    }
    // One tab, whether it came from tabs.json or from an agents.json row.
    function normalizeTab(t, i) {
        const state = t.state || (t.needs_you ? "waiting" : "");
        return {
            key: String(t.tab_id != null ? t.tab_id : (t.key || i)),
            index: t.index || i + 1,
            active: !!t.active,
            title: clean(t.title) || t.tab_title || t.agent || "Terminal",
            place: placeOf(t),
            project: t.project || "",
            hue: typeof t.hue === "string" && /^#[0-9A-Fa-f]{6}$/.test(t.hue) ? t.hue : "",
            agent: t.agent || "",
            brand: t.brand || "",
            state: state,
            age: t.age || ageFrom(t.since),
            progress: progressPct(t.progress),
            needsYou: !!t.needs_you || state === "waiting",
            limitReset: t.limit_reset || t.limitReset || null,
            question: t.question || "",
            panes: t.panes || 1,
            action: t.action || null
        };
    }
    function normalizeWindow(w) {
        return {
            kittyPid: w.kitty_pid || w.kittyPid || 0,
            osWindowId: w.os_window_id || w.osWindowId || 0,
            wmClass: w.wm_class || w.wmClass || "kitty",
            focused: !!w.focused,
            session: w.session || "",
            tabs: (w.tabs || []).map(normalizeTab)
        };
    }
    // No tabs.json yet: the agents the island already shows, one group per kitty.
    function fallbackTabs() {
        const raw = (live && feed && Array.isArray(feed.agents)) ? feed.agents : null;
        const list = raw || (running || []).map(a => ({
            key: a.key,
            kitty_pid: a.action && a.action.pid,
            agent: a.agent,
            brand: a.brand || "",
            state: a.state || (a.working ? "working" : "idle"),
            title: a.title,
            cwd: a.where || "",
            question: a.question || "",
            progress: a.progress,
            needs_you: a.state === "waiting" || /needs you/i.test(a.status || ""),
            action: a.action
        }));
        const groups = {};
        const order = [];
        list.forEach((a, i) => {
            const pid = String(a.kitty_pid || 0);
            if (!groups[pid]) { groups[pid] = { session: a.session || "", tabs: [] }; order.push(pid); }
            if (a.session && !groups[pid].session) groups[pid].session = a.session;
            groups[pid].tabs.push(normalizeTab(a, i));
        });
        return order.map(pid => ({
            kittyPid: Number(pid) || 0,
            osWindowId: 0,
            wmClass: "kitty",
            focused: true,
            session: groups[pid].session,
            tabs: groups[pid].tabs
        }));
    }
    readonly property var tabs: tabsLive ? tabsDoc.windows.map(normalizeWindow) : fallbackTabs()

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
        path: root.available ? root.stateDir + "/tabs.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.tabsDoc = JSON.parse(text()); } catch (e) {}
        }
        onLoadFailed: root.tabsDoc = null        // not written yet: `tabs` falls back to running agents
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
