// The launcher, grown out of the island (Super+A; replaces rofi's app
// finder). One field, one list: apps, open windows, the rice's own actions
// and a calculator, ranked by the clipboard's fuzzy matcher and by how often
// and how lately you used each (frecency). Empty, it shows what you use most.
//
//   ⌕  term│
//   ▣ Kitty              Terminal                     ↵
//   ▣ Kitty — ~/Projects  Window
//   = 1.5 × 4  → 6        Copy
//
// Keys: type to search, ↑↓ (or ⌃J ⌃K, ⌃N ⌃P, Tab) choose, ↵ open, Esc close.
// Uses: ~/.local/state/rice/launcher.json (counts and times, nothing else).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

FocusScope {
    id: launcher
    focus: true

    property string query: ""

    // ── Files (fd over your home), a moment after you stop typing ────────
    readonly property string home: Quickshell.env("HOME") || ""
    property var fileHits: []
    onQueryChanged: { fileHits = []; if (query.trim().length >= 3 && !/^[:;]/.test(query)) fileSoon.restart(); else fileSoon.stop(); }
    Timer { id: fileSoon; interval: 160; onTriggered: { files.running = false; files.running = true; } }
    Process {
        id: files
        // The query is an argument ("$1"), never part of the command.
        command: ["sh", "-c", "cd \"$HOME\" && timeout 1.5 fd --ignore-case --max-results 8 --max-depth 6 --exclude node_modules --exclude .cache --exclude .git --exclude .local/share/Steam --exclude .npm --exclude .cargo --exclude .rustup -- \"$1\" 2>/dev/null", "sh", launcher.query.trim()]
        stdout: StdioCollector {
            onStreamFinished: launcher.fileHits = text.split("\n").filter(x => x).map(rel => {
                const isDir = rel.endsWith("/");
                const clean = rel.replace(/\/$/, "");
                const cut = clean.lastIndexOf("/");
                return { kind: "file", path: launcher.home + "/" + clean, dir: isDir, name: cut >= 0 ? clean.slice(cut + 1) : clean,
                         sub: "~/" + (cut >= 0 ? clean.slice(0, cut) : ""), glyph: isDir ? "\u{f024b}" : "\u{f0214}" };
            })
        }
    }
    // Claude / Codex in the folder of the window you came from (bin/kuwai-agent).
    function agentHere(name) {
        const t = Hyprland.activeToplevel;
        const pid = t && t.lastIpcObject && t.lastIpcObject.pid ? String(t.lastIpcObject.pid) : "";
        Island.close();
        Quickshell.execDetached([Paths.bin + "/kuwai-agent", name, pid]);
    }
    // When this panel appeared: rows cascade in only during the first moment.
    readonly property real born: Date.now()
    property int current: 0
    property var lastPointer: null
    readonly property int rowH: 50
    readonly property int maxRows: 7

    // A fixed height: a launcher is used a hundred times a day, so it never
    // resizes under your typing (Raycast doesn't either).
    implicitWidth: 640
    implicitHeight: 64 + maxRows * rowH + 46

    // ── Frecency (kept by the Island service, which outlives this panel) ─
    function frecency(id) { return Island.frecency(id); }
    function used(id) { Island.used(id); }

    // ── Sources ──────────────────────────────────────────────────────────
    readonly property var apps: DesktopEntries.applications.values.filter(e => !e.noDisplay)
    readonly property var actions: [
        { name: "Lock Screen", sub: "Lock now", glyph: "\u{f033e}", run: () => Quickshell.execDetached(["loginctl", "lock-session"]) },
        { name: "Power", sub: "Sleep, restart, shut down", glyph: "\u{f0425}", run: () => Qt.callLater(() => Island.open("power", Island.screen, "key")), keep: true },
        { name: "Settings", sub: "Bar, clock, notifications, motion", glyph: "\u{f0493}", run: () => Qt.callLater(() => Island.open("settings", Island.screen, "key")), keep: true },
        { name: "Themes", sub: "Switch the theme or the wallpaper", glyph: "\u{f03d8}", run: () => Qt.callLater(() => { Island.themeMode = "themes"; Island.open("theme", Island.screen, "key"); }), keep: true },
        { name: "System", sub: "CPU, memory, GPU, updates", glyph: "\u{f0ee0}", run: () => Qt.callLater(() => Island.open("system", Island.screen, "key")), keep: true },
        { name: "Keyboard Shortcuts", sub: "Every Hyprland and rice shortcut", glyph: "\u{f030c}", run: () => Qt.callLater(() => Island.open("keys", Island.screen, "key")), keep: true },
        { name: "Calendar", sub: "This month", glyph: "\u{f00ed}", run: () => Qt.callLater(() => Island.open("calendar", Island.screen, "key")), keep: true },
        { name: "Clipboard", sub: "History and pins", glyph: "\u{f014c}", run: () => Clipboard.toggle("all") },
        { name: "Screen Recording", sub: "Choose a screen, audio and frame rate", glyph: "\u{f044a}", run: () => Clipboard.recordKey() },
        { name: "Screenshot", sub: "Pick an area or a window, then annotate", glyph: "\u{f0104}", run: () => Quickshell.execDetached([Paths.bin + "/rice-shot", "area"]) },
        { name: "Notifications", sub: "The center", glyph: "\u{f009a}", run: () => Notifs.toggleCenter("notifications", "key") },
        { name: "Claude here", sub: "Claude Code in this folder, as a kittymux tab", glyph: "\u{f06a9}", run: () => launcher.agentHere("claude") },
        { name: "Codex here", sub: "Codex in this folder, as a kittymux tab", glyph: "\u{f06a9}", run: () => launcher.agentHere("codex") },
        { name: "Agents", sub: "Every running agent and what needs you", glyph: "\u{f0e7b}", run: () => Notifs.toggleCenter("agents", "key") },
        { name: "Software Update", sub: "Review and install updates", glyph: "\u{f06b0}", run: () => Qt.callLater(() => Island.open("updates", Island.screen, "key")), keep: true },
        { name: "Update everything now", sub: "Arch, AUR without review, Flatpak: in the background", glyph: "\u{f0e4f}", run: () => Updates.runAll() },
        { name: "Update in a terminal", sub: "sysup", glyph: "\u{f018d}", run: () => Updates.terminal() },
        { name: "Do Not Disturb", sub: Notifs.dnd ? "On: turn off" : "Off: turn on", glyph: "\u{f0594}", run: () => { Notifs.dnd = !Notifs.dnd; } },
        { name: "Sound", sub: "Outputs, inputs, the microphone", glyph: "\u{f057e}", run: () => Notifs.toggleCenter("sound", "key") }
    ]

    // ── Conversions: "5 km to mi", "72 f in c", "100 usd to inr" ────────
    // Units are offline; currencies use open.er-api.com's daily rates (no
    // key, nothing about you is sent), cached 12 h in ~/.cache/rice/fx.json.
    readonly property var units: ({
        // length (m)
        mm: ["len", 0.001], cm: ["len", 0.01], m: ["len", 1], km: ["len", 1000], in: ["len", 0.0254], inch: ["len", 0.0254], ft: ["len", 0.3048], feet: ["len", 0.3048], yd: ["len", 0.9144], mi: ["len", 1609.344], mile: ["len", 1609.344], miles: ["len", 1609.344],
        // mass (g)
        mg: ["mass", 0.001], g: ["mass", 1], kg: ["mass", 1000], lb: ["mass", 453.59237], lbs: ["mass", 453.59237], oz: ["mass", 28.349523125], t: ["mass", 1e6],
        // data (bytes)
        b: ["data", 1], kb: ["data", 1e3], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12], kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824], tib: ["data", 1099511627776],
        // time (s)
        ms: ["time", 0.001], s: ["time", 1], sec: ["time", 1], min: ["time", 60], h: ["time", 3600], hr: ["time", 3600], d: ["time", 86400], day: ["time", 86400], days: ["time", 86400], wk: ["time", 604800], week: ["time", 604800],
        // volume (l)
        ml: ["vol", 0.001], l: ["vol", 1], gal: ["vol", 3.785411784], cup: ["vol", 0.2365882365], floz: ["vol", 0.0295735295625],
        // speed (m/s)
        kmh: ["speed", 1 / 3.6], mph: ["speed", 0.44704], mps: ["speed", 1], knot: ["speed", 0.514444], knots: ["speed", 0.514444]
    })
    readonly property string fxPath: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/rice/fx.json"
    property var fx: null                 // { base: "USD", time, rates: { INR: 83.1, … } }
    FileView {
        id: fxFile
        path: launcher.fxPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const d = JSON.parse(text()); if (d && d.rates) launcher.fx = { time: (d.time_last_update_unix || 0) * 1000, rates: d.rates }; } catch (e) {} }
    }
    Process {
        id: fxFetch
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && curl -sf --max-time 6 https://open.er-api.com/v6/latest/USD -o \"$1.tmp\" && mv -f \"$1.tmp\" \"$1\"", "sh", launcher.fxPath]
    }
    readonly property var convert: {
        const m = /^(-?[\d.,]+)\s*([a-z°]+)\s*(?:to|in|->|=|as)\s*([a-z°]+)$/i.exec(query.trim());
        if (!m) return null;
        const v = Number(m[1].replace(/,/g, ""));
        if (!isFinite(v)) return null;
        const a = m[2].toLowerCase().replace("°", ""), b = m[3].toLowerCase().replace("°", "");
        const fmt = x => { const r = Math.abs(x) >= 100 ? Math.round(x * 100) / 100 : Math.round(x * 1e4) / 1e4; return r.toLocaleString(Qt.locale(), "f", Math.abs(r) >= 100 ? 2 : 4).replace(/\.?0+$/, ""); };
        // Temperature isn't a ratio.
        const tc = { c: x => x, f: x => (x - 32) * 5 / 9, k: x => x - 273.15 }, fc = { c: x => x, f: x => x * 9 / 5 + 32, k: x => x + 273.15 };
        if (tc[a] && fc[b]) return { value: fmt(fc[b](tc[a](v))) + " °" + b.toUpperCase().replace("K", "K"), sub: m[1] + " °" + a.toUpperCase() + " =" };
        const ua = units[a], ub = units[b];
        if (ua && ub && ua[0] === ub[0]) return { value: fmt(v * ua[1] / ub[1]) + " " + m[3], sub: m[1] + " " + m[2] + " =" };
        // Currencies: three-letter codes.
        if (/^[a-z]{3}$/.test(a) && /^[a-z]{3}$/.test(b)) {
            const stale = !fx || Date.now() - fx.time > 12 * 3600 * 1000;
            if (stale && !fxFetch.running) Qt.callLater(() => { fxFetch.running = true; });
            if (!fx) return { value: "…", sub: "Fetching today's rates", pending: true };
            const A = a.toUpperCase(), B = b.toUpperCase(), ra = fx.rates[A], rb = fx.rates[B];
            if (!ra || !rb) return null;
            return { value: fmt(v / ra * rb) + " " + B, sub: m[1] + " " + A + " = · rates of " + Qt.formatDate(new Date(fx.time), "MMM d") };
        }
        return null;
    }

    // "timer 10m pizza", "25m", "1h30m tea": a timer row (services/Timers).
    readonly property var timerRow: {
        const m = /^(?:timer\s+)?(\d+(?:\.\d+)?\s*(?:h|hr|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)(?:\s*\d+\s*(?:m|min|s|sec))?|\d+:\d{2})(?:\s+(.+))?$/i.exec(query.trim());
        if (!m) { const t = /^timer\s+(\d+)(?:\s+(.+))?$/i.exec(query.trim()); if (!t) return null; return { secs: +t[1] * 60, name: t[2] || "" }; }
        const secs = Timers.parse(m[1]);
        return secs > 0 ? { secs: secs, name: m[2] || "" } : null;
    }

    // "remind me at 5 to call mum", "in 20m stretch", "tomorrow 9am dentist" (services/Reminders).
    readonly property var remindRow: /^(remind\b|in\s+\d|tomorrow\s+\d)/i.test(query.trim()) ? Reminders.parse(query) : null
    // "alarm 7:30", "alarm 6am gym" (services/Alarms).
    readonly property var alarmRow: /^alarm\s+\d/i.test(query.trim()) ? Alarms.parse(query) : null
    // "note buy milk": a line in ~/Notes/inbox.md (services/Notes).
    readonly property string noteText: { const m = /^note\s+(.+)$/i.exec(query.trim()); return m ? m[1] : ""; }
    // "pomodoro" / "pomo": 25 min work, 5 min break, ×4, then 15 (services/Timers).
    readonly property bool pomoRow: /^(pomodoro|pomo)$/i.test(query.trim())

    // A plain arithmetic expression (digits, + - * / % ^ ( ) .) and its value.
    readonly property var calc: {
        const q = query.trim().replace(/×/g, "*").replace(/÷/g, "/").replace(/,/g, ".");
        if (!/^[\d\s+\-*/().%^]+$/.test(q) || !/\d/.test(q) || !/[+\-*/%^]/.test(q)) return null;
        try {
            const v = Function('"use strict"; return (' + q.replace(/\^/g, "**") + ");")();
            if (typeof v !== "number" || !isFinite(v)) return null;
            return { expr: q, value: Math.round(v * 1e10) / 1e10 };
        } catch (e) { return null; }
    }

    // How well `needle` matches: the name fuzzily (letters in order, word
    // starts count most); the other fields (generic name, keywords) only as
    // a whole word start, so "fire" finds Firefox, not every app whose
    // description has an f, an i, an r and an e somewhere.
    function score(needle, name, others) {
        const n = String(name || "").toLowerCase();
        let best = null, pos = [];
        const m = Clipboard.fuzzy(needle, n);
        if (m) {
            // Contiguous and at a word start beats scattered letters.
            const at = n.indexOf(needle);
            best = m.score + (at === 0 ? 60 : at > 0 && /[\s\-_.]/.test(n[at - 1]) ? 40 : at > 0 ? 15 : 0);
            pos = at >= 0 ? Array.from({ length: needle.length }, (_, k) => at + k) : m.pos;
        }
        for (const f of others || []) {
            const t = String(f || "").toLowerCase();
            const at = t.search(new RegExp("(^|[\\s\\-_.,;])" + needle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
            if (at >= 0 && (best === null || 18 * needle.length > best)) best = Math.max(best || 0, 18 * needle.length);
        }
        return best === null ? null : { score: best, pos: pos };
    }

    // One list, in sections: the best match first (Top Hit), then by kind.
    // Empty: what you open most, then the rice's actions. Section headers are
    // rows the selection skips.
    readonly property var results: {
        const q = query.trim().toLowerCase();
        const out = [];
        const section = (title, rows) => { if (rows.length) out.push({ kind: "header", name: title }, ...rows); };
        // `:` emoji, `;` Nerd-font glyphs (HyDE's databases, services/Glyphs).
        if (query.startsWith(":") || query.startsWith(";")) {
            const emo = query.startsWith(":");
            if (emo) Glyphs.wantEmoji = true; else Glyphs.wantGlyphs = true;
            const hits = Glyphs.search(emo ? Glyphs.emoji : Glyphs.glyphs, query.slice(1), 60);
            section(emo ? "Emoji" : "Glyphs", hits.map(e => ({ kind: emo ? "emoji" : "glyph", name: e.name, sub: emo ? "Emoji" : "Nerd Font glyph", ch: e.ch, glyph: e.ch })));
            return out;
        }
        if (!q) {
            const top = apps.map(e => ({ e: e, f: frecency(e.id) })).filter(x => x.f > 0).sort((a, b) => b.f - a.f).slice(0, 5);
            section("Frequent", top.map(x => ({ kind: "app", entry: x.e, name: x.e.name, sub: x.e.genericName || x.e.comment || "", icon: x.e.icon })));
            section("Actions", actions.slice().sort((a, b) => frecency("action:" + b.name) - frecency("action:" + a.name)).slice(0, 4)
                                      .map(a => ({ kind: "action", action: a, name: a.name, sub: a.sub, glyph: a.glyph })));
            // Every app, A to Z, to browse instead of search (scroll or ↓).
            section("All Applications", apps.slice().sort((a, b) => a.name.localeCompare(b.name))
                                            .map(e => ({ kind: "app", entry: e, name: e.name, sub: e.genericName || e.comment || "", icon: e.icon })));
            return out;
        }
        const appsHit = [], winHit = [], actHit = [];
        for (const e of apps) {
            const m = score(q, e.name, [e.genericName, (e.keywords || []).join(" "), e.id]);
            if (m) appsHit.push({ kind: "app", entry: e, name: e.name, pos: m.pos, sub: e.genericName || e.comment || "", icon: e.icon, rank: m.score + Math.min(40, frecency(e.id) * 8) });
        }
        for (const t of Hyprland.toplevels.values) {
            const cls = t.lastIpcObject ? (t.lastIpcObject.class || "") : "";
            const app = cls ? DesktopEntries.heuristicLookup(cls) : null;
            const m = score(q, t.title, [cls, app ? app.name : ""]);
            if (m) winHit.push({ kind: "window", toplevel: t, name: t.title || cls, pos: m.pos, sub: (app ? app.name : cls) + (t.workspace && t.workspace.id > 0 ? " · workspace " + ((t.workspace.id - 1) % 10 + 1) : ""), icon: app ? app.icon : cls.toLowerCase(), rank: m.score * 0.85 });
        }
        for (const a of actions) {
            const m = score(q, a.name, [a.sub]);
            if (m) actHit.push({ kind: "action", action: a, name: a.name, pos: m.pos, sub: a.sub, glyph: a.glyph, rank: m.score * 0.9 + Math.min(20, frecency("action:" + a.name) * 4) });
        }
        // Weak matches go when a strong one exists (fuzzy noise).
        const all = [...appsHit, ...winHit, ...actHit];
        const bestRank = all.reduce((b, r) => Math.max(b, r.rank), 0);
        const keep = r => r.rank >= bestRank * 0.35;
        const by = rows => rows.filter(keep).sort((a, b) => b.rank - a.rank);
        if (calc) section("Calculator", [{ kind: "calc", name: String(calc.value), sub: calc.expr + " =", glyph: "=" }]);
        if (timerRow) section("Timer", [{ kind: "timer", name: "Start a " + Timers.label(timerRow.secs) + " timer" + (timerRow.name ? " · " + timerRow.name : ""), sub: "In the island, with a ring", glyph: "\u{f13ab}", secs: timerRow.secs, label: timerRow.name }]);
        if (remindRow) section("Reminder", [{ kind: "remind", name: "Remind me " + Reminders.when(remindRow.at) + " · " + remindRow.text, sub: "In the island and as a notification", glyph: "\u{f009a}" }]);
        if (alarmRow) section("Alarm", [{ kind: "alarm", name: "Alarm " + Qt.formatDateTime(new Date(alarmRow.at), new Date(alarmRow.at).getDate() === new Date().getDate() ? "HH:mm" : "ddd HH:mm") + (alarmRow.label !== "Alarm" ? " · " + alarmRow.label : ""), sub: Alarms.canWake ? "Wakes the laptop if it's asleep" : "Rings when the laptop is awake (sudo system/install to wake it)", glyph: "\u{f0020}" }]);
        if (noteText) section("Note", [{ kind: "note", name: "Note “" + noteText + "”", sub: "Added to " + Notes.file.replace(Quickshell.env("HOME"), "~"), glyph: "\u{f0219}", text: noteText }]);
        if (pomoRow) section("Focus", [{ kind: "pomo", name: Timers.pomo ? "Stop the pomodoro" : "Start a pomodoro", sub: "25 min work · 5 min break · ×4, then 15", glyph: "\u{f13ab}" }]);
        if (convert) section("Convert", [{ kind: "calc", name: convert.value, sub: convert.sub, glyph: "\u{f0a12}" }]);
        const top = all.filter(keep).sort((a, b) => b.rank - a.rank)[0];
        if (top) section("Top Hit", [top]);
        section("Applications", by(appsHit).filter(r => r !== top).slice(0, 8));
        section("Windows", by(winHit).filter(r => r !== top).slice(0, 5));
        section("Actions", by(actHit).filter(r => r !== top).slice(0, 4));
        section("Files", fileHits);
        // Last: the web, for anything the machine doesn't have.
        if (!calc && !convert && !timerRow && !remindRow && !alarmRow && !noteText && !pomoRow) section("Web", [{ kind: "web", name: "Search the web for “" + query.trim() + "”", sub: "DuckDuckGo", glyph: "\u{f059f}" }]);
        return out;
    }
    readonly property int selectable: results.filter(r => r.kind !== "header").length
    // New results snap: the selection lands on the first real row and the list
    // is back at the top on the same frame. No highlight travels between
    // keystrokes (DESIGN.md: searching snaps, no choreography between keys) —
    // each row draws its own selection, like Spotlight.
    onResultsChanged: {
        current = results.findIndex(r => r.kind !== "header");
        list.positionViewAtBeginning();
    }

    function run(r) {
        if (!r) return;
        if (r.kind === "emoji" || r.kind === "glyph") {
            // Typed into the window you came from once the island lets go of
            // the keyboard, and left on the clipboard too.
            Quickshell.execDetached(["wl-copy", "--", r.ch]);
            Quickshell.execDetached(["sh", "-c", "sleep 0.18; wtype -- \"$1\"", "sh", r.ch]);
        } else if (r.kind === "calc") {
            Quickshell.execDetached(["wl-copy", r.name]);
        } else if (r.kind === "app") {
            used(r.entry.id);
            r.entry.execute();
        } else if (r.kind === "timer") {
            Timers.start(r.secs, r.label);
        } else if (r.kind === "remind") {
            Reminders.add(query);
        } else if (r.kind === "alarm") {
            Alarms.add(query);
        } else if (r.kind === "note") {
            Notes.add(r.text);
        } else if (r.kind === "pomo") {
            Timers.pomo ? Timers.stopPomo() : Timers.startPomo();
        } else if (r.kind === "file") {
            Quickshell.execDetached(["xdg-open", r.path]);
        } else if (r.kind === "web") {
            Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(query.trim())]);
        } else if (r.kind === "window") {
            Hyprland.dispatch("hl.dsp.focus({window = 'address:0x" + r.toplevel.address + "'})");
        } else if (r.kind === "action") {
            used("action:" + r.name);
            if (!r.action.keep) Island.close();
            r.action.run();
            return;
        }
        Island.close();
    }
    function marked(name, pos) {
        const esc = c => c === "<" ? "&lt;" : c === ">" ? "&gt;" : c === "&" ? "&amp;" : c;
        const hit = new Set(pos);
        let out = "";
        for (let i = 0; i < name.length; i++)
            out += hit.has(i) ? "<font color=\"" + Theme.accent + "\">" + esc(name[i]) + "</font>" : esc(name[i]);
        return out;
    }
    function move(d) {
        if (!selectable) return;
        let i = current;
        do { i = (i + d + results.length) % results.length; } while (results[i].kind === "header");
        current = i;
        list.positionViewAtIndex(current, ListView.Contain);
        if (current <= 1) list.positionViewAtBeginning();
    }

    // ── Search ───────────────────────────────────────────────────────────
    Item {
        id: search
        x: 18; y: 12
        width: parent.width - 36
        height: 40
        Text {
            id: lens
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f0349}"
            font.family: Theme.fontGlyph
            font.pixelSize: 18
            color: Theme.textTertiary
        }
        TextInput {
            id: field
            anchors { left: lens.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
            focus: true
            font.family: Theme.fontText
            font.pixelSize: 19
            font.variableAxes: ({ "opsz": Theme.opszFor(19), "wght": Theme.wRegular })
            color: Theme.textPrimary
            selectionColor: Qt.rgba(1, 1, 1, 0.25)
            selectedTextColor: Theme.textPrimary
            cursorDelegate: Rectangle { width: 2; radius: 1; color: Theme.blue; visible: field.cursorVisible }
            onTextChanged: { launcher.query = text; Island.lastQuery = text; }
            // The last search comes back, selected: typing replaces it, ↵ repeats it.
            Component.onCompleted: {
                if (Island.prefill) { text = Island.prefill; cursorPosition = text.length; Island.prefill = ""; }
                else { text = Island.lastQuery; selectAll(); }
            }
            Keys.onPressed: event => {
                const k = event.key, ctrl = event.modifiers & Qt.ControlModifier;
                if (k === Qt.Key_Down || k === Qt.Key_Tab || (ctrl && (k === Qt.Key_J || k === Qt.Key_N))) launcher.move(1);
                else if (k === Qt.Key_Up || k === Qt.Key_Backtab || (ctrl && (k === Qt.Key_K || k === Qt.Key_P))) launcher.move(-1);
                else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && launcher.results[launcher.current] && launcher.results[launcher.current].kind === "file" && (ctrl || (event.modifiers & Qt.AltModifier))) {
                    // A file: Ctrl+↩ its folder, Alt+↩ copy its path.
                    const r = launcher.results[launcher.current];
                    if (ctrl) Quickshell.execDetached(["xdg-open", r.dir ? r.path : r.path.slice(0, r.path.lastIndexOf("/"))]);
                    else Quickshell.execDetached(["wl-copy", "--", r.path]);
                    Island.close();
                }
                else if (k === Qt.Key_Return || k === Qt.Key_Enter) launcher.run(launcher.results[launcher.current]);
                else return;
                event.accepted = true;
            }
            Label {
                visible: !field.text
                anchors.verticalCenter: parent.verticalCenter
                text: "Search apps, windows, actions   :emoji   ;glyphs"
                size: 19
                color: Theme.textTertiary
            }
        }
    }
    Rectangle { x: 0; y: 63; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

    // ── Results ──────────────────────────────────────────────────────────
    ListView {
        id: list
        x: 8; y: 64
        width: parent.width - 16
        height: launcher.maxRows * launcher.rowH
        clip: true
        model: launcher.results
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: -1
        highlightFollowsCurrentItem: false

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool on: index === launcher.current
            readonly property bool header: modelData.kind === "header"
            width: list.width
            height: header ? 30 : launcher.rowH

            // First paint after opening: rows cascade in (20 ms apart, the
            // first nine), rising 6 px. Afterwards results just appear —
            // typing must never replay this.
            property real enter: 1
            opacity: enter
            transform: Translate { y: 6 * (1 - row.enter) }
            Component.onCompleted: if (!Theme.reduceMotion && Date.now() - launcher.born < 260 && index < 9) { enter = 0; cascade.start(); }
            SequentialAnimation {
                id: cascade
                PauseAnimation { duration: 40 + row.index * 20 }
                NumberAnimation { target: row; property: "enter"; to: 1; duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            }

            // Selection: drawn by the row itself, so it can't travel or flicker
            // when the results change under it. Keyboard/pointer moves fade it
            // across in 90ms; a new result list shows it already in place.
            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 2; anchors.rightMargin: 2
                radius: 12
                visible: !row.header
                color: Qt.rgba(1, 1, 1, 0.10)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)
                opacity: row.on ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 90; easing.type: Easing.OutCubic } }
            }

            Label {
                visible: row.header
                x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                text: row.modelData.name
                size: 11; weight: Theme.wSemibold; color: Theme.textTertiary
                extraTracking: 0.4
            }

            Item {
                id: iconBox
                visible: !row.header
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32
                readonly property string path: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                IconImage { anchors.fill: parent; visible: iconBox.path !== ""; source: iconBox.path; asynchronous: true }
                Rectangle {
                    visible: iconBox.path === ""
                    anchors.fill: parent; radius: 9
                    color: Theme.pill
                    Text {
                        anchors.centerIn: parent
                        text: row.modelData.glyph || "\u{f0b2a}"
                        font.family: row.modelData.kind === "calc" ? Theme.fontRounded : row.modelData.kind === "emoji" ? "Noto Color Emoji" : Theme.fontGlyph
                        font.pixelSize: row.modelData.kind === "calc" ? 18 : row.modelData.kind === "emoji" ? 22 : 17
                        color: Theme.textSecondary
                    }
                }
            }
            Column {
                visible: !row.header
                anchors { left: iconBox.right; leftMargin: 12; right: hint.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 1
                // The letters you typed, in the accent.
                Label {
                    width: parent.width; elide: Text.ElideRight
                    textFormat: row.modelData.pos && row.modelData.pos.length ? Text.StyledText : Text.PlainText
                    text: row.modelData.pos && row.modelData.pos.length ? launcher.marked(row.modelData.name, row.modelData.pos) : row.modelData.name
                    size: row.modelData.kind === "calc" ? 17 : 14; weight: Theme.wMedium; rounded: row.modelData.kind === "calc"
                }
                Label { visible: text !== ""; width: parent.width; elide: Text.ElideRight; text: row.modelData.sub || ""; size: 12; color: Theme.textTertiary }
            }
            Row {
                id: hint
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8
                opacity: row.on && !row.header ? 1 : 0
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ({ app: "Open", window: "Switch to", action: "Run", calc: "Copy", emoji: "Type", glyph: "Type", file: "Open", web: "Search", timer: "Start" })[row.modelData.kind] || ""
                    size: 12
                    color: Theme.textSecondary
                }
                KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "↩" }
            }
            MouseArea {
                anchors.fill: parent
                enabled: !row.header
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // Only a pointer that moves picks: one resting where the list
                // opens must not steal the selection from the keyboard.
                // (Qt also reports a "move" when rows appear under a still
                // pointer: compare screen positions.)
                onPositionChanged: mouse => {
                    const g = mapToGlobal(mouse.x, mouse.y);
                    const was = launcher.lastPointer;
                    launcher.lastPointer = g;
                    if (was && (g.x !== was.x || g.y !== was.y)) launcher.current = row.index;
                }
                onClicked: launcher.run(row.modelData)
            }
        }

        Label {
            visible: launcher.selectable === 0 && launcher.query.trim() !== ""
            anchors.centerIn: parent
            text: "No results for “" + launcher.query.trim() + "”"
            size: 13
            color: Theme.textTertiary
        }
    }

    // ── Footer ───────────────────────────────────────────────────────────
    Rectangle { x: 0; y: parent.height - 46; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }
    Row {
        anchors { left: parent.left; leftMargin: 20; bottom: parent.bottom; bottomMargin: 14 }
        spacing: 16
        Repeater {
            model: launcher.results[launcher.current] && launcher.results[launcher.current].kind === "file"
                ? [["↩", "Open"], ["⌃↩", "Folder"], ["⌥↩", "Copy path"], ["esc", "Close"]]
                : [["↑↓", "Choose"], ["↩", "Open"], ["esc", "Close"]]
            Row {
                required property var modelData
                spacing: 6
                KeyCap { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0] }
                Label { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1]; size: 12; color: Theme.textTertiary }
            }
        }
    }
    Label {
        anchors { right: parent.right; rightMargin: 20; bottom: parent.bottom; bottomMargin: 15 }
        text: launcher.query ? launcher.selectable + (launcher.selectable === 1 ? " result" : " results") : ""
        size: 12
        color: Theme.textTertiary
    }
}
