pragma Singleton

// Usage limits, the way T3 Code shows them: providers, each with every
// signed-in account, each with its windows. Read-only, from T3 Code itself
// (bin/rice-usage --watch holds its config subscription: T3 Code pushes
// changes, nothing polls), or from kittymux when T3 Code isn't there.
//
//   providers: [{ driver, label, color, accounts: [{ key, name, email, plan,
//                note, credits, windows: [{ id, kind, label, used, resetsAt,
//                durationMins }] }] }]
//
// Always connected (cheap: T3 Code pushes, nothing polls). If rice-usage
// dies the last state stays and it comes back with a backoff (2 s → 5 min);
// `down` says it isn't running, for the Usage panel's error and Retry.
//
// Limit alerts (Settings.limitAlerts, threshold Settings.limitThreshold):
//   approaching (≥ threshold)  one Moment per window per reset period
//   exhausted (100 %)          one Moment, then a mark on the notch
//                              (IslandRest) until it resets
//   reset                      a quiet Moment, the mark goes
// What was said is kept in ~/.local/state/rice/limits-told.json, so a
// restart doesn't say it again.
// (The pragma sits above this comment: Quickshell's scanner stops at the
// first brace, comments included.)
import QtQuick
import Quickshell
import qs.config
import Quickshell.Io

Singleton {
    id: root

    readonly property bool watching: true       // always (callers read it)
    property bool loaded: false                 // the first snapshot has arrived
    property var providers: []
    property string source: ""                 // t3 | kittymux | none
    property real now: Date.now()               // advanced on each read and each minute tick, not per frame
    property string error: ""                   // why T3 Code isn't the source, if it isn't

    // rice-usage itself: alive, or down (died, waiting to come back).
    property bool alive: false
    property int fails: 0
    readonly property bool down: !alive && fails > 0

    // Something is showing a countdown (the Usage panel, the center's Agents
    // tab): the minute tick runs for it.
    property bool panelShown: false
    property bool centerShown: false

    readonly property string bin: Paths.bin + "/rice-usage"
    readonly property string toldPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/rice/limits-told.json"

    // Every window, flat: [{ key, provider, account, window, used (0–1),
    // name ("Claude weekly"), level: "" | "approaching" | "exhausted" }].
    readonly property real threshold: Math.max(0.5, Math.min(0.99, (Settings.limitThreshold || 80) / 100))
    readonly property var windows: {
        const out = [];
        for (const p of providers)
            for (const a of p.accounts || [])
                for (const w of a.windows || []) {
                    const used = Math.max(0, Math.min(1, (w.used || 0) / 100));
                    const over = !!w.resetsAt && w.resetsAt <= now;   // its reset passed; the data hasn't caught up
                    out.push({ key: alertKey(p, a, w), provider: p, account: a, window: w, used: over ? 0 : used,
                               name: shortName(p, w),
                               level: over ? "" : used >= 1 ? "exhausted" : used >= threshold ? "approaching" : "" });
                }
        return out;
    }
    // One per window: two accounts on one shared quota (Antigravity's
    // "Claude & GPT (shared)") reported it twice, so it was said twice.
    readonly property var exhausted: {
        const seen = {}, out = [];
        for (const x of windows) {
            if (x.level !== "exhausted") continue;
            const k = x.name + "|" + Math.round((x.window.resetsAt || 0) / 600000);
            if (seen[k]) continue;
            seen[k] = true; out.push(x);
        }
        return out;
    }
    // The brands that are used up, one each, soonest reset first: the
    // notch's stacked logos ("which agent is out", not a bare gauge).
    readonly property var exhaustedBrands: {
        const by = {};
        for (const x of exhausted) {
            const b = brandFor(x.provider);
            const r = x.window.resetsAt || Infinity;
            if (!by[b] || r < by[b].resetsAt) by[b] = { brand: b, name: providerShort(x.provider), resetsAt: r };
        }
        return Object.values(by).sort((a, b) => a.resetsAt - b.resetsAt);
    }
    // A provider's brand mark (shell/assets/brands), "" for none.
    readonly property string brandDir: Qt.resolvedUrl("../assets/brands")
    // The agent's colour (Theme.brandTint), the text colour when unknown.
    function tintFor(p) {
        const b = brandFor(p).replace(/^.*\//, "").replace(/\.svg$/, "");
        return Theme.brandTint[b] || Theme.textPrimary;
    }
    function brandFor(p) {
        const n = String((p && (p.driver || p.label)) || "").toLowerCase();
        const f = /claude/.test(n) ? "claude" : /codex|openai|gpt/.test(n) ? "openai" : /cursor/.test(n) ? "cursor"
            : /antigravity|agy/.test(n) ? "antigravity" : /grok/.test(n) ? "grok" : /gemini/.test(n) ? "googlegemini"
            : /opencode/.test(n) ? "opencode" : /kimi/.test(n) ? "kimi" : /qwen/.test(n) ? "qwen" : "";
        return f ? brandDir + "/" + f + ".svg" : "";
    }
    // The soonest reset among exhausted windows (ms from now, -1 if none known).
    readonly property real soonestReset: {
        const t = exhausted.map(x => x.window.resetsAt).filter(r => r > now).sort((a, b) => a - b);
        return t.length ? t[0] - now : -1;
    }
    // What the notch shows: alerts on and something used up.
    readonly property bool markShown: Settings.limitAlerts && exhausted.length > 0

    IpcHandler {
        target: "limits"
        function state(): string {
            return JSON.stringify({ alive: root.alive, fails: root.fails, source: root.source, error: root.error,
                                    exhausted: root.exhausted.map(x => x.name),
                                    providers: root.providers.map(p => p.label + ":" + p.accounts.length) });
        }
        function retry(): void { root.retry(); }
    }

    // Countdowns move once a minute, and only while one is on screen or a
    // window is used up (its reset has to be noticed); never per second.
    Timer {
        interval: 60000
        repeat: true
        running: root.exhausted.length > 0 || root.panelShown || root.centerShown
        onTriggered: { root.now = Date.now(); root.scan(); }
    }
    onPanelShownChanged: if (panelShown) now = Date.now()
    onCenterShownChanged: if (centerShown) now = Date.now()

    Process {
        id: reader
        command: [root.bin, "--watch"]
        property real since: 0
        onStarted: { root.alive = true; since = Date.now(); }
        onExited: {
            root.alive = false;
            // A run that lasted a while was healthy: start the backoff over.
            if (Date.now() - since > 120000) root.fails = 0;
            root.fails += 1;
            backoff.interval = Math.min(300000, 2000 * Math.pow(2, Math.min(8, root.fails - 1)));
            backoff.start();
        }
        stdout: SplitParser {
            onRead: line => {
                let d;
                try { d = JSON.parse(line); } catch (e) { return; }
                root.now = Date.now();
                root.source = d.source || "";
                root.error = d.t3Error || "";
                root.providers = d.providers || [];
                root.loaded = true;
                root.scan();
            }
        }
    }
    Timer { id: backoff; onTriggered: reader.running = true }
    function retry() { backoff.stop(); fails = 0; if (!reader.running) reader.running = true; }
    Component.onCompleted: reader.running = true

    // ── Alerts ────────────────────────────────────────────────────────────
    // told: { key: { resetsAt, name, approach, exhausted } }, one entry per
    // window while its period lasts.
    property var told: ({})
    property bool toldLoaded: false
    FileView {
        id: toldFile
        path: root.toldPath
        printErrors: false
        onLoaded: { try { root.told = JSON.parse(text()) || {}; } catch (e) { root.told = {}; } root.toldLoaded = true; root.scan(); }
        onLoadFailed: { root.toldLoaded = true; root.scan(); }
    }
    function saveTold() {
        if (!toldLoaded) return;
        toldDir.running = true;
    }
    Process { id: toldDir; command: ["mkdir", "-p", root.toldPath.replace(/\/[^/]*$/, "")]; onExited: toldFile.setText(JSON.stringify(root.told)) }

    // Moments only once they're armed (a startup snapshot isn't news yet:
    // it's said a few seconds later), and not under Focus or while sharing
    // (the mark still shows: it's the memory).
    Connections { target: Moments; function onArmedChanged() { if (Moments.armed) root.scan(); } }
    Connections { target: Settings; function onLimitAlertsChanged() { root.scan(); } }

    function say(x, value, tone, ms) {
        if (Notifs.muted) return;
        // The agent's logo leads; its ring fills to how much is used (a reset:
        // a full green ring), the way the island shows any live gauge.
        const reset = value === "reset";
        Moments.show({ kind: "limit:" + x.key, image: brandFor(x.provider), glyph: "\u{f029a}", label: x.name,
                       value: value, ring: reset ? 1 : x.used, tone: reset ? Theme.green : tone }, ms);
    }

    function scan() {
        if (!loaded || !toldLoaded || !Moments.armed || !Settings.limitAlerts) return;
        const t = Object.assign({}, told);
        let changed = false;
        const seen = {};
        const said = {};                 // a shared window on two accounts: said once
        for (const x of windows) {
            seen[x.key] = true;
            const prev = t[x.key];
            const r = x.window.resetsAt || 0;
            // Reset: used dropped under the line or its reset time passed
            // (level ""), or it's reporting a later period than the one we
            // told about (the shell was off across the reset). Small drift in
            // resetsAt (kittymux recomputes it each read) isn't a new period.
            const later = prev && prev.resetsAt && r && r - prev.resetsAt > 3600000;
            const once = x.name + "|" + Math.round(r / 600000);
            if (prev && (x.level === "" || later)) {
                if (prev.exhausted && !said[once]) { said[once] = true; say(x, "reset", Theme.textSecondary, 2800); }
                delete t[x.key];
                changed = true;
            }
            if (x.level === "") continue;
            const cur = t[x.key] || { resetsAt: r, name: x.name, approach: false, exhausted: false };
            if (said[once]) {
                const ex = x.level === "exhausted" || cur.exhausted;
                if (!t[x.key] || cur.exhausted !== ex || !cur.approach) { t[x.key] = Object.assign(cur, { exhausted: ex, approach: true }); changed = true; }
                continue;
            }
            said[once] = true;
            if (x.level === "exhausted" && !cur.exhausted) {
                say(x, "used up" + (r ? " · resets in " + resetsIn(x.window) : ""), Theme.orange, 6000);
                cur.exhausted = true; cur.approach = true;
            } else if (!cur.approach) {
                say(x, Math.round(x.used * 100) + "%" + (r ? " · resets " + resetDay(r) : ""), Theme.orange, 5000);
                cur.approach = true;
            } else continue;
            cur.resetsAt = r || cur.resetsAt;
            t[x.key] = cur;
            changed = true;
        }
        // A window no longer reported: forgotten once its reset has passed.
        for (const k of Object.keys(t)) {
            if (seen[k] || !t[k].resetsAt || t[k].resetsAt > now) continue;
            if (t[k].exhausted && !Notifs.muted)
                Moments.show({ kind: "limit:" + k, glyph: "\u{f029a}", label: t[k].name, value: "reset", ring: 1, tone: Theme.green }, 2800);
            delete t[k];
            changed = true;
        }
        if (changed) { told = t; saveTold(); }
    }

    function alertKey(p, a, w) {
        return (p.driver || p.label || "p") + ":" + (a.key || a.email || "") + ":" + (w.id || w.label || "");
    }
    // "Claude Code" + "Weekly" → "Claude weekly"; "5 hour" → "5-hour".
    function providerShort(p) { return String(p.label || p.driver || "Agent").replace(/\s+(Code|Build)$/, ""); }
    function windowLabel(w) { return String(w.label || w.kind || "Quota").replace(/^(\d+)\s+hour/i, "$1-hour"); }
    function shortName(p, w) { return providerShort(p) + " " + windowLabel(w).toLowerCase(); }
    // "Tue" a day or more away, else the time ("14:30").
    function resetDay(at) {
        const d = new Date(at);
        return at - now >= 86400000 ? Qt.formatDate(d, "ddd") : Qt.formatTime(d, Settings.clock24 ? "HH:mm" : "h:mm ap");
    }
    // The mark's value: the largest unit only ("3d", "15h", "42m").
    function compact(ms) {
        if (ms < 0) return "";
        const d = Math.floor(ms / 86400000), h = Math.floor(ms / 3600000), m = Math.max(1, Math.ceil(ms / 60000));
        return d > 0 ? d + "d" : h > 0 ? h + "h" : m + "m";
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
