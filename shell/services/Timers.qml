pragma Singleton

// Timers for the island: "Pizza · 4:12" with a ring, then a moment and a
// sound when one ends. Started from the launcher ("timer 10m pizza", "25m")
// or `rice timer 10m pizza`. Kept across shell restarts in
// $XDG_RUNTIME_DIR/rice/timers.json (not across a logout).
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var timers: []          // [{ id, label, start: ms, end: ms }], soonest first
    readonly property var next: timers.length ? timers[0] : null
    property real now: Date.now()

    // "10m", "1h30m", "90s", "1:30", "25" (minutes) → seconds, or 0.
    function parse(s) {
        s = String(s || "").trim().toLowerCase();
        let m = /^(\d+):(\d{1,2})$/.exec(s);
        if (m) return +m[1] * 60 + +m[2];
        if (/^\d+(\.\d+)?$/.test(s)) return Math.round(+s * 60);
        let total = 0, any = false;
        const rx = /(\d+(?:\.\d+)?)\s*(h|hr|hrs|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)/g;
        for (let r = rx.exec(s); r; r = rx.exec(s)) {
            any = true;
            const u = r[2][0];
            total += +r[1] * (u === "h" ? 3600 : u === "m" ? 60 : 1);
        }
        return any ? Math.round(total) : 0;
    }
    function label(secs) {
        const h = Math.floor(secs / 3600), m = Math.round(secs % 3600 / 60);
        return h ? h + " h" + (m ? " " + m + " min" : "") : secs >= 60 ? Math.round(secs / 60) + " min" : secs + " s";
    }
    function start(secs, name) {
        if (!(secs > 0)) return;
        const t = Date.now();
        timers = [...timers, { id: t, label: name || label(secs), start: t, end: t + secs * 1000 }].sort((a, b) => a.end - b.end);
        save();
    }
    function cancel(id) { timers = timers.filter(t => t.id !== id); save(); }
    function remaining(t) { return t ? Math.max(0, (t.end - now) / 1000) : 0; }
    function fraction(t) { return t ? Math.max(0, Math.min(1, (t.end - now) / Math.max(1, t.end - t.start))) : 0; }
    function clock(secs) {
        const s = Math.ceil(secs), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), ss = String(s % 60).padStart(2, "0");
        return h ? h + ":" + String(m).padStart(2, "0") + ":" + ss : m + ":" + ss;
    }

    signal finished(var t)
    Timer {
        interval: 250; repeat: true; running: root.timers.length > 0
        onTriggered: {
            root.now = Date.now();
            const done = root.timers.filter(t => t.end <= root.now);
            if (!done.length) return;
            root.timers = root.timers.filter(t => t.end > root.now);
            root.save();
            for (const t of done) { root.finished(t); ding.running = true; }
        }
    }
    Process { id: ding; command: ["pw-play", "--volume", "0.8", "/usr/share/sounds/freedesktop/stereo/complete.oga"] }

    // ── Kept across shell restarts ───────────────────────────────────────
    readonly property string file: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice/timers.json"
    property bool loaded: false
    FileView {
        id: store
        path: root.file
        printErrors: false
        onLoaded: { try { root.timers = (JSON.parse(text()) || []).filter(t => t.end > Date.now()); } catch (e) {} root.loaded = true; }
        onLoadFailed: root.loaded = true
    }
    function save() { if (loaded) store.setText(JSON.stringify(timers)); }

    IpcHandler {
        target: "timer"
        // `rice timer 10m pizza` · `rice timer cancel`
        function start(spec: string, name: string): string {
            const s = root.parse(spec);
            if (!s) return "can't read " + spec;
            root.start(s, name);
            return "timer: " + root.label(s);
        }
        function cancel(): void { if (root.next) root.cancel(root.next.id); }
        function list(): string { return JSON.stringify(root.timers); }
    }
}
