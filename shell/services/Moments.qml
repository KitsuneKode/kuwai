pragma Singleton

// Brief moments the island shows by itself, Apple's compact activities: one
// thing on the left, its state on the right, for a few seconds.
//
//   🎧 (earbuds / your IEMs' photo)        ◯ 80 %   connected, battery ring
//   ☾  Focus                                  On    Do Not Disturb on / off
//   Low Battery                        20 %  ▭      on battery, at 20 %
//
// `now` is the moment showing ({ kind, glyph, image, label, value, ring, tone })
// or null. IslandRest draws it; anything urgent (a password) still wins.
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs.config

Singleton {
    id: root

    property var now: null
    function show(m, ms) {
        now = m;
        hide.interval = ms || 3200;
        hide.restart();
    }
    Timer { id: hide; onTriggered: root.now = null }

    // Nothing at startup: devices and settings arriving aren't news.
    property bool armed: false
    Timer { interval: 4000; running: true; onTriggered: root.armed = true }

    // ── Headphones and earbuds connecting ───────────────────────────────
    readonly property var connected: Bluetooth.devices.values.filter(d => d.connected)
    property var known: []
    onConnectedChanged: {
        const addrs = connected.map(d => d.address);
        const fresh = connected.filter(d => known.indexOf(d.address) < 0);
        known = addrs;
        if (!armed) return;
        for (const d of fresh) if (audioLike(d)) { pending = d; settle.restart(); }
    }
    function audioLike(d) {
        const s = ((d.icon || "") + " " + (d.name || "")).toLowerCase();
        return /audio|head|ear|buds|pods|speaker|wf-|wh-/.test(s) || !!DeviceArt.lookup(d.name || "");
    }
    // BlueZ reports the battery a moment after the link comes up.
    property var pending: null
    Timer {
        id: settle
        interval: 1500
        onTriggered: {
            const d = root.pending;
            if (!d || !d.connected) return;
            const art = DeviceArt.lookup(d.name || d.deviceName || "");
            const s = ((d.icon || "") + " " + (d.name || "")).toLowerCase();
            const buds = /buds|pods|wf-|ear|tws/.test(s) || (art && (art.kind === "earbuds" || art.kind === "iem"));
            root.show({
                kind: "device",
                glyph: /speaker/.test(s) ? "\u{f04c3}" : buds ? "\u{f184f}" : "\u{f02cb}",
                image: art ? art.image : "",
                label: art ? art.label : (d.name || d.deviceName),
                ring: d.batteryAvailable ? d.battery : -1,
                value: d.batteryAvailable ? Math.round(d.battery * 100) + "%" : "Connected",
                tone: d.batteryAvailable && d.battery <= 0.2 ? Theme.red : Theme.green
            }, 3600);
        }
    }

    // ── Focus (Do Not Disturb) ──────────────────────────────────────────
    Connections {
        target: Notifs
        function onDndChanged() {
            if (!root.armed || !Notifs.loaded) return;
            root.show({ kind: "focus", glyph: "\u{f0594}", label: "Focus", value: Notifs.dnd ? "On" : "Off", ring: -1, tone: "#bf5af2" }, 2400);
        }
    }

    // ── Caffeine (Super+\, Super+Shift+C, Controls, the cup) ───────────
    // In place of the old "Caffeine Mode · Activated" notification.
    Connections {
        target: Caffeine
        function onOnChanged() {
            if (!root.armed || !Caffeine.loaded) return;
            root.show({ kind: "caffeine", glyph: "\u{f0176}", label: "Caffeine", value: Caffeine.on ? "On" : "Off", ring: -1, tone: Caffeine.on ? Theme.yellow : Theme.textSecondary }, 2400);
        }
    }

    // ── An event soon (services/Calendar): "Standup · in 10 min" ─────────
    // Ten minutes before, and again as it starts. Each once.
    property var announced: ({})
    Timer {
        interval: 30000; repeat: true; running: Calendar.events.length > 0; triggeredOnStart: true
        onTriggered: {
            const now = Date.now();
            for (const e of Calendar.events) {
                if (e.allDay) continue;
                const left = e.start - now;
                const key10 = e.start + "|" + e.title + "|10", key0 = e.start + "|" + e.title + "|0";
                if (left > 0 && left <= 10 * 60000 && left > 8 * 60000 && !root.announced[key10]) {
                    root.announced[key10] = true;
                    root.show({ kind: "event", glyph: "\u{f00ed}", label: e.title, value: "in " + Math.ceil(left / 60000) + " min", ring: -1, tone: Theme.textPrimary }, 6000);
                } else if (left <= 0 && left > -60000 && !root.announced[key0]) {
                    root.announced[key0] = true;
                    root.show({ kind: "event", glyph: "\u{f00ed}", label: e.title, value: "Now", ring: -1, tone: Theme.green }, 6000);
                }
            }
        }
    }

    // ── Power and network: plugged in, and the connection coming and going ─
    property bool wasOnBattery: UPower.onBattery
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            const plugged = root.wasOnBattery && !UPower.onBattery;
            root.wasOnBattery = UPower.onBattery;
            if (!root.armed || !plugged) return;
            root.show({ kind: "battery", label: "Charging", value: root.pct + "%", ring: -1, tone: Theme.green, glyph: "\u{f0084}" }, 2600);
        }
    }
    // Online is a quick NetworkManager check, every 20 s and on any change.
    property bool online: true
    property bool onlineKnown: false
    Process {
        id: netCheck
        command: ["nmcli", "-t", "-f", "CONNECTIVITY", "general"]
        stdout: StdioCollector {
            onStreamFinished: {
                const now = /full|limited|portal/.test(text);
                if (root.onlineKnown && now !== root.online && root.armed)
                    root.show(now ? { kind: "net", glyph: "\u{f05a9}", label: "Back online", value: "", ring: -1, tone: Theme.green }
                                  : { kind: "net", glyph: "\u{f05aa}", label: "Offline", value: "", ring: -1, tone: Theme.red }, now ? 2200 : 4000);
                root.online = now;
                root.onlineKnown = true;
            }
        }
    }
    Timer { interval: 20000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!netCheck.running) netCheck.running = true }

    // ── Agents (kittymux's inbox): one needs you, or finished ───────────
    // Each event once, newest only; the brand mark, the agent and its tab.
    property real agentSeen: Date.now() / 1000
    Connections {
        target: Kittymux
        function onInboxChanged() {
            const fresh = (Kittymux.inbox.events || []).filter(e => e.status === "unread" && e.t > root.agentSeen).sort((a, b) => b.t - a.t);
            if (!fresh.length) return;
            root.agentSeen = fresh[0].t;
            if (!root.armed) return;
            const e = fresh[0];
            const needs = e.severity === "needs-you";
            const name = String(e.agent || "Agent");
            root.show({
                kind: "agent", image: Kittymux.brand(e.agent), glyph: "\u{f06a9}",
                label: name.charAt(0).toUpperCase() + name.slice(1),
                value: needs ? (e.kind === "permission" ? "Needs you" : "Waiting") : e.kind === "limit" ? "Hit a limit" : "Done",
                ring: -1, tone: needs || e.kind === "limit" ? Theme.orange : Theme.green
            }, needs ? 6000 : 3000);
        }
    }

    // ── Timers (services/Timers) ending ─────────────────────────────────
    Connections {
        target: Timers
        function onFinished(t) { root.show({ kind: "timer", glyph: "\u{f13ab}", label: t.label, value: "Done", ring: -1, tone: Theme.green }, 6000); }
    }

    // ── Low battery (20 %, on battery; 10 % is the Alerts banner) ────────
    readonly property var battery: UPower.displayDevice
    readonly property int pct: battery && battery.isLaptopBattery && battery.isPresent ? Math.round(battery.percentage > 1 ? battery.percentage : battery.percentage * 100) : 100
    property bool warned: false
    onPctChanged: {
        if (!UPower.onBattery || pct > 25) { warned = false; return; }
        if (armed && !warned && pct <= 20) {
            warned = true;
            show({ kind: "battery", label: "Low Battery", value: pct + "%", ring: -1, tone: Theme.red, glyph: "" }, 5000);
        }
    }
}
