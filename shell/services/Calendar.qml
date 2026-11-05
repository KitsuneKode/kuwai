pragma Singleton

// Your calendars' events, for the calendar panel and the island's "in 10
// min" moment. Sources: ~/.config/rice/calendars.txt, one per line, each an
// iCal link (Google Calendar's "Secret address in iCal format", Outlook,
// iCloud, Fastmail…) or a local .ics path; # starts a comment. Links are
// fetched every 30 minutes into ~/.cache/rice/calendars/ (only the link
// itself is requested; nothing else leaves the machine).
//
// Parsing is the small useful part of iCalendar: VEVENTs with DTSTART/DTEND
// (dates, local times, UTC "Z" times; a TZID is read as local time), SUMMARY,
// LOCATION, and RRULE FREQ=DAILY/WEEKLY/MONTHLY/YEARLY with INTERVAL, COUNT,
// UNTIL and BYDAY (weekly), minus EXDATEs, expanded from yesterday to 60 days.
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string listPath: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/rice/calendars.txt"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/rice/calendars"

    property var events: []          // [{ start: ms, end: ms, title, location, allDay }], sorted
    property bool configured: false

    // ── Sources ──────────────────────────────────────────────────────────
    FileView {
        id: list
        path: root.listPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.refresh()
        onLoadFailed: { root.configured = false; root.events = []; }
    }
    readonly property var sources: (list.loaded ? list.text() : "").split("\n").map(l => l.trim()).filter(l => l && !l.startsWith("#"))

    // Fetch the links, then read every calendar (fetched and local) as one
    // stream with a marker between files.
    function refresh() {
        configured = sources.length > 0;
        if (!configured) { events = []; return; }
        if (!fetch.running) fetch.running = true;
    }
    Process {
        id: fetch
        // Sources are arguments ("$@"), never part of the command.
        command: ["sh", "-c", `
            dir=$1; shift; mkdir -p "$dir"; i=0
            for src in "$@"; do
                i=$((i + 1))
                case $src in
                    http://*|https://*|webcal://*)
                        url=$(printf %s "$src" | sed 's#^webcal://#https://#')
                        curl -sfL --max-time 15 --max-filesize 8M --proto =https,http --proto-redir =https "$url" -o "$dir/$i.ics.tmp" && mv -f "$dir/$i.ics.tmp" "$dir/$i.ics"
                        f="$dir/$i.ics" ;;
                    "~/"*) f="$HOME/\${src#\\~/}" ;;
                    *) f=$src ;;
                esac
                [ -r "$f" ] && { cat "$f"; printf '\\nX-RICE-END-OF-FILE\\n'; }
            done`, "sh", root.cacheDir, ...root.sources]
        stdout: StdioCollector { onStreamFinished: root.events = root.parse(text) }
    }
    Timer { interval: 30 * 60 * 1000; running: root.configured; repeat: true; onTriggered: root.refresh() }

    // ── iCalendar, the useful part ───────────────────────────────────────
    function parseTime(v, params) {
        // 20261104 (a date) · 20261104T093000 (local) · 20261104T093000Z (UTC)
        const m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/.exec(v || "");
        if (!m) return null;
        const [y, mo, d, h, mi, s, z] = [m[1], m[2], m[3], m[4], m[5], m[6], m[7]];
        if (h === undefined) return { ms: new Date(+y, +mo - 1, +d).getTime(), allDay: true };
        if (z) return { ms: Date.UTC(+y, +mo - 1, +d, +h, +mi, +(s || 0)), allDay: false };
        return { ms: new Date(+y, +mo - 1, +d, +h, +mi, +(s || 0)).getTime(), allDay: false };
    }
    function icsText(t) { return String(t || "").replace(/\\n/gi, " ").replace(/\\([,;\\])/g, "$1").trim(); }

    function parse(text) {
        // Unfold continuation lines (a line starting with a space continues the last).
        const lines = text.replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "").split("\n");
        const from = Date.now() - 86400000, to = Date.now() + 60 * 86400000;
        const out = [];
        let ev = null;
        for (const raw of lines) {
            if (raw === "BEGIN:VEVENT") { ev = { exdates: [] }; continue; }
            if (raw === "END:VEVENT") { if (ev) expand(ev, from, to, out); ev = null; continue; }
            if (!ev) continue;
            const c = raw.indexOf(":");
            if (c < 0) continue;
            const head = raw.slice(0, c), value = raw.slice(c + 1);
            const name = head.split(";")[0].toUpperCase();
            if (name === "SUMMARY") ev.title = icsText(value);
            else if (name === "LOCATION") ev.location = icsText(value);
            else if (name === "DTSTART") ev.start = parseTime(value);
            else if (name === "DTEND") ev.end = parseTime(value);
            else if (name === "RRULE") ev.rrule = value;
            else if (name === "EXDATE") for (const x of value.split(",")) { const t = parseTime(x); if (t) ev.exdates.push(t.ms); }
            else if (name === "STATUS") ev.cancelled = value.toUpperCase() === "CANCELLED";
        }
        out.sort((a, b) => a.start - b.start);
        return out;

        function expand(e, lo, hi, into) {
            if (!e.start || e.cancelled) return;
            const dur = e.end ? Math.max(0, e.end.ms - e.start.ms) : (e.start.allDay ? 86400000 : 3600000);
            const push = s => {
                if (s + dur < lo || s > hi || e.exdates.indexOf(s) >= 0) return;
                into.push({ start: s, end: s + dur, title: e.title || "(No title)", location: e.location || "", allDay: e.start.allDay });
            };
            if (!e.rrule) { push(e.start.ms); return; }
            const r = {};
            for (const kv of e.rrule.split(";")) { const [k, v] = kv.split("="); r[k.toUpperCase()] = v; }
            const freq = r.FREQ, step = Math.max(1, +(r.INTERVAL || 1));
            const until = r.UNTIL ? (parseTime(r.UNTIL) || { ms: hi }).ms : hi;
            let count = r.COUNT ? +r.COUNT : Infinity;
            const days = r.BYDAY ? r.BYDAY.split(",").map(d => ["SU", "MO", "TU", "WE", "TH", "FR", "SA"].indexOf(d.slice(-2))) : null;
            const base = new Date(e.start.ms);
            for (let k = 0, guard = 0; guard < 2000 && count > 0; k++, guard++) {
                const d = new Date(base);
                if (freq === "DAILY") d.setDate(base.getDate() + k * step);
                else if (freq === "WEEKLY") d.setDate(base.getDate() + k * 7 * step);
                else if (freq === "MONTHLY") d.setMonth(base.getMonth() + k * step);
                else if (freq === "YEARLY") d.setFullYear(base.getFullYear() + k * step);
                else { push(e.start.ms); return; }
                if (d.getTime() > until || d.getTime() > hi) return;
                if (freq === "WEEKLY" && days && days.length) {
                    // Each listed weekday of this week (week starting on the base's weekday).
                    for (let w = 0; w < 7 && count > 0; w++) {
                        const x = new Date(d); x.setDate(d.getDate() + w);
                        if (days.indexOf(x.getDay()) < 0 || x.getTime() < e.start.ms || x.getTime() > until) continue;
                        count--; push(x.getTime());
                    }
                } else { count--; push(d.getTime()); }
            }
        }
    }

    // The events of a day (any that overlap it).
    function eventsOn(day) {
        const a = new Date(day.getFullYear(), day.getMonth(), day.getDate()).getTime(), b = a + 86400000;
        return events.filter(e => e.start < b && e.end > a);
    }
    function timeOf(e) {
        if (e.allDay) return "All day";
        const f = t => Qt.formatTime(new Date(t), Qt.locale().timeFormat(Locale.ShortFormat).indexOf("AP") >= 0 ? "h:mm AP" : "HH:mm");
        return f(e.start) + " – " + f(e.end);
    }
}
