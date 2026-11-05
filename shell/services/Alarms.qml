pragma Singleton

// Alarms: a time of day that rings until you stop it, through the lock
// screen too. "alarm 7:30", "alarm 6am gym" in the launcher, or
// `rice alarm 7:30 gym`. Kept in ~/.local/share/rice/alarms.json.
// Asleep: with system/install's rice-wake, the next alarm is written to
// /var/lib/rice-wake/at and the RTC wakes the laptop for it (without it,
// alarms ring when the laptop is next awake, and the island says so).
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    property var items: []                    // [{ id, label, at: ms }], soonest first
    readonly property var next: items.length ? items[0] : null
    property var ringing: null                // the alarm ringing now
    property bool canWake: false              // rice-wake installed (the file is ours to write)

    // "7:30", "6am", "18:05 tea" → { at, label } (the next time it comes round).
    function parse(input) {
        const m = /^(?:alarm\s+)?(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b\s*(.*)$/i.exec(String(input || "").trim());
        if (!m) return null;
        let h = +m[1], min = +(m[2] || 0);
        const ap = (m[3] || "").toLowerCase();
        if (h > 23 || min > 59 || (ap && h > 12)) return null;
        if (ap === "pm" && h < 12) h += 12;
        if (ap === "am" && h === 12) h = 0;
        const d = new Date();
        d.setHours(h, min, 0, 0);
        if (d <= new Date()) d.setDate(d.getDate() + 1);
        return { at: d.getTime(), label: m[4].trim() || "Alarm" };
    }
    function add(input) {
        const a = parse(input);
        if (!a) return null;
        items = [...items, { id: Date.now(), label: a.label, at: a.at }].sort((x, y) => x.at - y.at);
        save();
        return a;
    }
    function cancel(id) { items = items.filter(i => i.id !== id); save(); }

    // ── Ringing ──────────────────────────────────────────────────────────
    function ring(a) {
        ringing = a;
        Moments.show({ kind: "alarm", glyph: "\u{f0020}", label: a.label, value: Qt.formatTime(new Date(a.at), Settings.clock24 ? "HH:mm" : "h:mm"), ring: -1, tone: Theme.orange }, 15000);
        asker.createObject(root, { alarm: a });
    }
    function stop() { ringing = null; }
    function snooze(mins) {
        if (!ringing) return;
        const a = ringing;
        ringing = null;
        items = [...items, { id: Date.now(), label: a.label, at: Date.now() + mins * 60000 }].sort((x, y) => x.at - y.at);
        save();
    }
    // The sound, again and again while it rings (5 minutes at most).
    Timer {
        interval: 2600; repeat: true; triggeredOnStart: true
        running: root.ringing !== null
        onTriggered: {
            if (Date.now() - root.ringing.at > 5 * 60000) { root.stop(); return; }
            bell.running = true;
        }
    }
    Process { id: bell; command: ["pw-play", "--volume", "1.0", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"] }
    Component {
        id: asker
        Process {
            property var alarm
            running: true
            command: [Paths.bin + "/rice-notify", "-w", "-a", "Alarm", "-i", "alarm-symbolic", "-u", "critical",
                      "-A", "stop=Stop", "-A", "snooze=Snooze 9 min", alarm.label, Qt.formatTime(new Date(alarm.at), Settings.clock24 ? "HH:mm" : "h:mm AP")]
            stdout: StdioCollector { id: said }
            onExited: {
                if (root.ringing && root.ringing.id === alarm.id) {
                    if (said.text.trim() === "snooze") root.snooze(9); else root.stop();
                }
                destroy();
            }
        }
    }
    Timer {
        interval: 5000; repeat: true; triggeredOnStart: true
        running: root.items.length > 0
        onTriggered: {
            const now = Date.now();
            const due = root.items.filter(i => i.at <= now);
            if (!due.length) return;
            root.items = root.items.filter(i => i.at > now);
            root.save();
            // Missed by more than an hour (the laptop was off): say so, don't ring.
            const fresh = due.filter(a => now - a.at < 3600000);
            for (const a of due) if (now - a.at >= 3600000)
                Quickshell.execDetached([Paths.bin + "/rice-notify", "-a", "Alarm", "-i", "alarm-symbolic", "Missed alarm", a.label + " · " + Qt.formatTime(new Date(a.at), "HH:mm")]);
            if (fresh.length) root.ring(fresh[fresh.length - 1]);
        }
    }

    // ── Kept, and the wake time for the RTC ──────────────────────────────
    readonly property string file: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/rice/alarms.json"
    readonly property string wakeFile: "/var/lib/rice-wake/at"
    property bool loaded: false
    FileView {
        id: store
        path: root.file
        printErrors: false
        onLoaded: { try { root.items = (JSON.parse(text()) || []).sort((a, b) => a.at - b.at); } catch (e) {} root.loaded = true; root.armWake(); }
        onLoadFailed: { root.loaded = true; root.armWake(); }
    }
    function save() {
        if (!loaded) return;
        mk.running = true;
        armWake();
    }
    Process { id: mk; command: ["mkdir", "-p", root.file.replace(/\/[^/]*$/, "")]; onExited: store.setText(JSON.stringify(root.items)) }
    // One number: the next alarm a minute early (time to resume), or 0.
    function armWake() {
        const t = next ? Math.floor(next.at / 1000) - 60 : 0;
        wake.command = ["sh", "-c", '[ -w "$1" ] || exit 3; printf %s "$2" > "$1"', "sh", wakeFile, String(t > Date.now() / 1000 + 30 ? t : 0)];
        wake.running = true;
    }
    Process { id: wake; onExited: code => root.canWake = code === 0 }

    IpcHandler {
        target: "alarm"
        function add(text: string): string { const a = root.add(text); return a ? a.label + " · " + Qt.formatDateTime(new Date(a.at), "ddd HH:mm") + (root.canWake ? "" : " (install system/install to wake from sleep)") : "can't read a time in: " + text; }
        function list(): string { return JSON.stringify(root.items); }
        function clear(): void { root.items = []; root.save(); }
        function stop(): void { root.stop(); }
        function snooze(): void { root.snooze(9); }
    }
}
