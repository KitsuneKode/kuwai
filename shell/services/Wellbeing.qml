// Wellbeing: two quiet nudges, never a nag.
//
// Breaks: after Settings.breakMins (50) of continuous use, one moment on the
// notch ("Time for a break · 50 min on screen"). Five idle minutes or a lock
// is a break and starts the count again. Never over a fullscreen video, a
// screen share or Focus: it waits, and asks again at most every 20 minutes.
//
// Sleep: past Settings.sleepAt (00:30) while you're still here, one calm
// moment ("It's late · time to wind down"), then at most two softer ones,
// 45 minutes apart. Reset each morning.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config

Singleton {
    id: root

    // ── Breaks ───────────────────────────────────────────────────────────
    property real activeSince: Date.now()
    property real lastNudge: 0
    readonly property bool holdOff: Notifs.muted || Notifs.fullscreenNow
    IdleMonitor {
        // Five minutes away is a break.
        enabled: Settings.breakReminders
        timeout: 300
        respectInhibitors: false
        onIsIdleChanged: if (isIdle) root.activeSince = Date.now()
    }
    // Here right now: used in the last two minutes.
    IdleMonitor { id: here; enabled: Settings.sleepReminder; timeout: 120; respectInhibitors: false }
    function rested() { activeSince = Date.now(); }     // a lock is a break (Lock.qml)

    Timer {
        interval: 60000; repeat: true
        running: Settings.breakReminders || Settings.sleepReminder
        onTriggered: { root.checkBreak(); root.checkSleep(); }
    }
    function checkBreak() {
        if (!Settings.breakReminders || holdOff) return;
        const mins = Math.round((Date.now() - activeSince) / 60000);
        const every = Math.max(20, Settings.breakMins || 50);
        if (mins < every || Date.now() - lastNudge < 20 * 60000) return;
        lastNudge = Date.now();
        Moments.show({ kind: "break", glyph: "\u{f0645}", label: "Time for a break",
                       value: (mins >= 60 ? Math.floor(mins / 60) + " h " + (mins % 60 ? mins % 60 + " min" : "") : mins + " min") + " on screen",
                       ring: -1, tone: Theme.green }, 5000);
    }

    // ── Sleep ────────────────────────────────────────────────────────────
    property int sleepSaid: 0
    property real sleepLast: 0
    property string sleepDay: ""
    function minutesOf(hm) { const p = String(hm || "00:30").split(":"); return (+p[0] || 0) * 60 + (+p[1] || 0); }
    function checkSleep() {
        if (!Settings.sleepReminder) return;
        const d = new Date();
        const now = d.getHours() * 60 + d.getMinutes();
        const at = minutesOf(Settings.sleepAt);
        // The night runs from sleepAt to 05:00.
        const night = at <= 300 ? (now >= at && now < 300) : (now >= at || now < 300);
        const day = Qt.formatDate(new Date(d.getTime() - 5 * 3600000), "yyyy-MM-dd");
        if (day !== sleepDay) { sleepDay = day; sleepSaid = 0; }
        if (!night || sleepSaid >= 3 || holdOff || here.isIdle || Date.now() - sleepLast < 45 * 60000) return;
        sleepSaid++;
        sleepLast = Date.now();
        Moments.show({ kind: "sleep", glyph: "\u{f0594}", label: sleepSaid === 1 ? "It's late" : "Still up",
                       value: sleepSaid === 1 ? "time to wind down" : Qt.formatTime(d, Settings.clock24 ? "HH:mm" : "h:mm ap"),
                       ring: -1, tone: Theme.indigo }, sleepSaid === 1 ? 5000 : 3600);
    }
}
