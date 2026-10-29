// Usage limits, the way T3 Code shows them: providers, each with every
// signed-in account, each with its windows (bin/rice-usage reads T3 Code's
// server, or kittymux when T3 Code isn't there).
//
//   providers: [{ driver, label, color, accounts: [{ key, name, email, plan,
//                note, credits, windows: [{ id, kind, label, used, resetsAt,
//                durationMins }] }] }]
//
// Read while the Agents tab is on screen (every minute) and whenever
// kittymux rewrites its usage file; nothing runs while it's closed.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool watching: false
    property var providers: []
    property string source: ""                 // t3 | kittymux | none
    property real now: Date.now()               // advanced on each read, not per frame

    readonly property string bin: Quickshell.env("HOME") + "/Projects/rice/bin/rice-usage"

    function refresh() { if (!reader.running) reader.running = true; }
    onWatchingChanged: if (watching) refresh()

    Timer {
        interval: 60000
        repeat: true
        running: root.watching
        onTriggered: root.refresh()
    }
    // Countdowns move on their own between reads.
    Timer {
        interval: 30000
        repeat: true
        running: root.watching
        onTriggered: root.now = Date.now()
    }

    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/kittymux/agent-usage.json"
        watchChanges: true
        printErrors: false
        onFileChanged: if (root.watching) root.refresh()
    }

    Process {
        id: reader
        command: [root.bin]
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }
                root.now = Date.now();
                root.source = d.source || "";
                root.providers = d.providers || [];
            }
        }
    }

    // ── T3 Code's arithmetic (packages/shared/src/usageLimits.ts) ─────────
    function remaining(w) { return Math.round(100 - Math.max(0, Math.min(100, w.used))); }
    // Share of the window already elapsed, if its length and reset are known.
    function elapsed(w) {
        if (!w.resetsAt || !w.durationMins) return -1;
        const len = w.durationMins * 60000;
        return Math.max(0, Math.min(1, (len - (w.resetsAt - now)) / len));
    }
    // Bars show quota remaining, so even pace tracks time remaining.
    function paceLeft(w) { const e = elapsed(w); return e < 0 ? -1 : Math.round((1 - e) * 100); }
    function pace(w) {
        const e = elapsed(w);
        if (e < 0) return "";
        const gap = w.used - e * 100;
        return gap > 5 ? "ahead" : gap < -5 ? "under" : "on";
    }
    function duration(ms) {
        ms = Math.max(0, ms);
        const d = Math.floor(ms / 86400000), h = Math.floor(ms % 86400000 / 3600000), m = Math.floor(ms % 3600000 / 60000);
        return d > 0 ? `${d}d ${h}h` : h > 0 ? `${h}h ${m}m` : `${m}m`;
    }
    function resetsIn(w) {
        if (!w.resetsAt) return "";
        return w.resetsAt <= now ? "now" : duration(w.resetsAt - now);
    }

    // One row per window across a provider's accounts (by id, session
    // windows first), each with that window's account members.
    function pool(provider) {
        const order = { session: 0, weekly: 1, monthly: 2, other: 3 };
        const rows = [];
        for (const a of provider.accounts) {
            for (const w of a.windows) {
                let r = rows.find(x => x.id === w.id);
                if (!r) { r = { id: w.id, kind: w.kind, label: w.label, members: [] }; rows.push(r); }
                r.members.push({ account: a, window: w });
            }
        }
        for (const r of rows) {
            r.remaining = Math.round(r.members.reduce((s, m) => s + remaining(m.window), 0) / r.members.length);
            // The soonest reset among accounts still waiting on one.
            const resets = r.members.map(m => m.window).filter(w => w.resetsAt && remaining(w) < 100).sort((a, b) => a.resetsAt - b.resetsAt);
            r.resetsIn = resets.length ? resetsIn(resets[0]) : "";
            r.pace = r.members.length === 1 ? pace(r.members[0].window) : "";
        }
        return rows.sort((a, b) => (order[a.kind] ?? 3) - (order[b.kind] ?? 3));
    }

    // Account identity: its name, else its email's initials on a hue of its
    // own (T3 Code's AccountChip).
    function initials(a) {
        if (a.name) return a.name.replace(/[^A-Za-z0-9]/g, "").slice(0, 2).toUpperCase() || "?";
        const [local, domain] = (a.email || "").split("@");
        return ((local || "")[0] || "").toUpperCase() + ((domain || "")[0] || "").toUpperCase() || "?";
    }
    function hue(a) {
        const s = a.email || a.name || a.key || "";
        let h = 0;
        for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
        return Math.abs(h) % 360;
    }
    function label(a) {
        return a.name || (a.email ? a.email.split("@")[0] : "") || "Account";
    }
}
