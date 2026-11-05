pragma Singleton

// Reminders, said the way you'd say them (the launcher, `rice remind …`):
//   "remind me at 5 to call mum"        today 17:00 (or 05:00 if it's before 5 am now)
//   "in 20m stretch" · "in 1h30m tea"    from now
//   "at 17:30 standup" · "5pm review"    today, or tomorrow if that time has passed
//   "tomorrow 9am dentist"               tomorrow
// Kept in ~/.local/share/rice/reminders.json (across restarts and sleep: a
// reminder due while asleep fires on waking). When one is due: a moment in
// the island and a notification you can snooze from the center.
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    property var items: []                    // [{ id, text, at: ms }], soonest first
    readonly property var next: items.length ? items[0] : null

    // ── Words → { at, text } or null ─────────────────────────────────────
    function parse(input) {
        let s = String(input || "").trim().replace(/^remind( me)?\s*/i, "").replace(/\s+/g, " ");
        if (!s) return null;
        const now = new Date();
        let at = null, rest = s;
        // in 20m / in 1h30m / in 2 hours
        let m = /^in\s+((?:\d+(?:\.\d+)?\s*(?:h|hr|hrs|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)\s*)+)\s*(?:to\s+)?(.*)$/i.exec(s);
        if (m) {
            const secs = Timers.parse(m[1]);
            if (secs > 0) { at = new Date(now.getTime() + secs * 1000); rest = m[2]; }
        }
        if (!at) {
            // [tomorrow] [at] 5 / 5pm / 17:30 / 5:30 pm [to] text
            m = /^(tomorrow\s+)?(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b\s*(?:tomorrow\s*)?(?:to\s+)?(.*)$/i.exec(s);
            if (m) {
                const tomorrow = !!m[1] || /\btomorrow\b/i.test(s.slice(0, s.length - m[5].length));
                let h = +m[2], min = +(m[3] || 0);
                const ap = (m[4] || "").toLowerCase();
                if (h > 23 || min > 59) return null;
                if (ap === "pm" && h < 12) h += 12;
                if (ap === "am" && h === 12) h = 0;
                const d = new Date(now);
                d.setSeconds(0, 0);
                if (tomorrow) d.setDate(d.getDate() + 1);
                d.setHours(h, min);
                // "at 5" with no am/pm: the next 5 o'clock that's ahead.
                if (!ap && !tomorrow && h < 12 && d <= now) { d.setHours(h + 12); }
                if (!tomorrow && d <= now) d.setDate(d.getDate() + 1);
                at = d; rest = m[5];
            }
        }
        if (!at) return null;
        rest = rest.replace(/^to\s+/i, "").trim();
        return { at: at.getTime(), text: rest || "Reminder" };
    }
    function when(ms) {
        const d = new Date(ms), now = new Date();
        const same = d.toDateString() === now.toDateString();
        const tmr = new Date(now); tmr.setDate(now.getDate() + 1);
        const day = same ? "today" : d.toDateString() === tmr.toDateString() ? "tomorrow" : Qt.formatDate(d, "ddd d MMM");
        return day + " at " + Qt.formatTime(d, Settings.clock24 ? "HH:mm" : "h:mm AP");
    }
    function add(input) {
        const r = parse(input);
        if (!r) return null;
        items = [...items, { id: Date.now() * 100 + items.length % 100, text: r.text, at: r.at }].sort((a, b) => a.at - b.at);
        save();
        return r;
    }
    function cancel(id) { items = items.filter(i => i.id !== id); save(); }
    function snooze(r, mins) {
        items = [...items, { id: Date.now() * 100 + items.length % 100, text: r.text, at: Date.now() + mins * 60000 }].sort((a, b) => a.at - b.at);
        save();
    }

    // The notification, with Snooze (10 min) and Done; it waits for the
    // answer (rice-notify -w prints the action's key) and then goes.
    Component {
        id: asker
        Process {
            property var reminder
            running: true
            command: [Paths.bin + "/rice-notify", "-w", "-a", "Reminders", "-i", "appointment-soon", "-u", "critical",
                      "-A", "snooze=Snooze 10 min", "-A", "done=Done", "Reminder", reminder.text]
            stdout: StdioCollector { id: said }
            onExited: { if (said.text.trim() === "snooze") root.snooze(reminder, 10); destroy(); }
        }
    }

    // ── Due ──────────────────────────────────────────────────────────────
    signal due(var r)
    Timer {
        interval: 15000; repeat: true; triggeredOnStart: true
        running: root.items.length > 0
        onTriggered: {
            const now = Date.now();
            const done = root.items.filter(i => i.at <= now);
            if (!done.length) return;
            root.items = root.items.filter(i => i.at > now);
            root.save();
            for (const r of done) {
                root.due(r);
                Moments.show({ kind: "reminder", glyph: "\u{f009a}", label: r.text, value: "Now", ring: -1, tone: Theme.orange }, 8000);
                asker.createObject(root, { reminder: r });
            }
        }
    }

    // ── Kept ─────────────────────────────────────────────────────────────
    readonly property string file: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/rice/reminders.json"
    property bool loaded: false
    FileView {
        id: store
        path: root.file
        printErrors: false
        onLoaded: { try { root.items = (JSON.parse(text()) || []).sort((a, b) => a.at - b.at); } catch (e) {} root.loaded = true; }
        onLoadFailed: root.loaded = true
    }
    function save() {
        if (!loaded) return;
        mk.running = true;
    }
    Process { id: mk; command: ["mkdir", "-p", root.file.replace(/\/[^/]*$/, "")]; onExited: store.setText(JSON.stringify(root.items)) }

    IpcHandler {
        target: "remind"
        function add(text: string): string { const r = root.add(text); return r ? r.text + " · " + root.when(r.at) : "can't read a time in: " + text; }
        function list(): string { return JSON.stringify(root.items); }
        function clear(): void { root.items = []; root.save(); }
    }
}
