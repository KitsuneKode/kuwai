pragma Singleton

// Brief moments the island shows by itself, Apple's compact activities: one
// thing on the left, its state on the right, for a few seconds.
//
//   ☾  Focus                                  On    Do Not Disturb on / off
//   Low Battery                        20 %  ▭      on battery, at 20 %
//
// `now` is the moment showing ({ kind, glyph, image, label, value, ring, tone })
// or null. IslandRest draws it; anything urgent (a password) still wins.
// Devices get more room: `card`, grown out of the island (DeviceCard).
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs.config

Singleton {
    id: root

    // One at a time, in order: a moment arriving while another shows waits
    // its turn, unless it's the same kind (Focus on, then off), which just
    // updates. Only the newest of each kind waits. "Copied" answers a key
    // press, so it cuts in and what it interrupted goes next.
    property var now: null
    property int nowMs: 0
    property var queue: []            // [{ m, ms }]
    function show(m, ms) {
        if (now && now.kind !== m.kind && m.kind === "copied") {
            queue = [{ m: now, ms: nowMs }].concat(queue);
            now = null;
        } else if (now && now.kind !== m.kind) {
            queue = queue.filter(q => q.m.kind !== m.kind).concat([{ m: m, ms: ms }]).slice(-3);
            return;
        }
        if (!now && gap.running) {
            queue = [{ m: m, ms: ms }].concat(queue.filter(q => q.m.kind !== m.kind));
            return;
        }
        now = m;
        nowMs = ms || 3200;
        hide.interval = nowMs;
        hide.restart();
    }
    // The island closes between two, so the next reads as new.
    Timer { id: hide; onTriggered: { root.now = null; if (root.queue.length) gap.start(); } }
    Timer {
        id: gap
        interval: 450
        onTriggered: {
            const q = root.queue[0];
            root.queue = root.queue.slice(1);
            if (q) root.show(q.m, q.ms);
        }
    }

    // Nothing at startup: devices and settings arriving aren't news.
    property bool armed: false
    Timer { interval: 4000; running: true; onTriggered: root.armed = true }

    // ── Devices: what's connected, as it happens ────────────────────────
    // A card grows out of the island (DeviceCard): the device's photo
    // (DeviceArt) or its kind, its name, what happened, its battery. For any
    // Bluetooth device connecting or going (earbuds, a speaker, a mouse, a
    // pad); the sound moving to another output (Osd says so: it knows the
    // IEMs behind a DAC); and once at login, what's already connected.
    //
    //   card: { key, glyph, image, title, state, tone, detail, battery (0..1 or -1), gone }
    property var card: null
    property bool cardHeld: false
    function showCard(c, ms) {
        // The same device again (its link, then its sound): fill in, don't replay.
        if (card && card.key === c.key && cardFor.running)
            card = Object.assign({}, card, c, { battery: c.battery >= 0 ? c.battery : card.battery, detail: c.detail || card.detail });
        else card = c;
        cardFor.interval = ms || 4000;
        cardFor.restart();
    }
    function dropCard() { cardFor.stop(); card = null; }
    Timer { id: cardFor; onTriggered: if (root.cardHeld) restart(); else root.card = null }

    readonly property var kindGlyph: ({
        earbuds: "\u{f184f}", iem: "\u{f184f}", headphones: "\u{f02cb}", speaker: "\u{f04c3}", car: "\u{f010b}",
        mouse: "\u{f037d}", keyboard: "\u{f030c}", gamepad: "\u{f0296}", phone: "\u{f011c}", watch: "\u{f0897}",
        usb: "\u{f0553}", laptop: "\u{f0322}", display: "\u{f0f5f}", bluetooth: "\u{f00af}"
    })
    // BlueZ calls most audio gear "audio-headset" (earbuds and speakers
    // alike), so the name decides first; devices.json beats both.
    function btKind(d) {
        const art = DeviceArt.lookup(d.name || "");
        if (art && art.kind) return art.kind;
        const s = ((d.icon || "") + " " + (d.name || "")).toLowerCase();
        if (/mouse|trackpad|mx (master|anywhere)/.test(s)) return "mouse";
        if (/keyboard|keychron|\bkeys\b/.test(s)) return "keyboard";
        if (/gaming|joystick|gamepad|controller|dualsense|dualshock|xbox|8bitdo|joy-con/.test(s)) return "gamepad";
        if (/phone|iphone|pixel|galaxy s/.test(s)) return "phone";
        if (/watch|band\b/.test(s)) return "watch";
        if (/buds|pods|\bwf-|earbud|\btws\b|freebuds|liberty|\biem\b/.test(s)) return "earbuds";
        if (/speaker|boost|\bflip|\bcharge|soundlink|soundcore|\bsrs-|boom/.test(s)) return "speaker";
        if (/audio|head|\bear|\bwh-|dac|btr|qudelix/.test(s)) return "headphones";
        return "bluetooth";
    }
    function btCard(d) {
        const name = d.name || d.deviceName || "Device";
        const art = DeviceArt.lookup(name);
        return { key: name.toLowerCase(), glyph: kindGlyph[btKind(d)], image: art ? art.image : "",
                 title: art ? art.label : name, state: "Connected", tone: Theme.green,
                 detail: art && art.via ? "via " + art.via : "", battery: d.batteryAvailable ? d.battery : -1, gone: false };
    }

    readonly property var connected: Bluetooth.devices.values.filter(d => d.connected)
    property var known: []            // [{ address, name, kind }]
    property var pending: []
    onConnectedChanged: {
        const now = connected.map(d => ({ address: d.address, name: d.name || d.deviceName || "Device", kind: btKind(d) }));
        const fresh = connected.filter(d => !known.some(k => k.address === d.address));
        const gone = known.filter(k => !now.some(n => n.address === k.address));
        known = now;
        if (!armed) return;
        for (const g of gone) deviceGone(g);
        if (fresh.length) { pending = pending.concat(fresh); settle.restart(); }
    }
    // BlueZ reports the battery a moment after the link comes up.
    Timer {
        id: settle
        interval: 1500
        onTriggered: {
            const ds = root.pending.filter(d => d.connected);
            root.pending = [];
            if (!ds.length) return;
            const c = root.btCard(ds[ds.length - 1]);
            if (ds.length > 1) c.detail = "and " + ds.slice(0, -1).map(d => d.name || "a device").join(", ");
            root.showCard(c);
        }
    }
    property var lastGone: null
    function deviceGone(g) {
        const art = DeviceArt.lookup(g.name);
        lastGone = { key: g.name.toLowerCase(), at: Date.now() };
        showCard({ key: lastGone.key, glyph: kindGlyph[g.kind], image: art ? art.image : "", title: art ? art.label : g.name,
                   state: "Disconnected", tone: Theme.textSecondary, detail: "", battery: -1, gone: true }, 3400);
    }
    // Osd, when the sound moves: { key, glyph, image, title, via, battery, live, boot }.
    // `live`: a device that comes and goes (Bluetooth, USB, a known DAC).
    function outputSwitched(o) {
        // Headphones just went: say where the sound went instead.
        if (lastGone && Date.now() - lastGone.at < 4000 && card && card.gone) {
            showCard(Object.assign({}, card, { detail: "Sound on " + o.title }), 3400);
            return;
        }
        showCard({ key: o.key, glyph: o.glyph, image: o.image, title: o.title,
                   state: o.live ? "Connected" : "Sound output", tone: o.live ? Theme.green : Theme.textSecondary,
                   detail: o.via ? "via " + o.via : "", battery: o.battery, gone: false }, o.live ? 4000 : 2600);
    }
    // Once, after the hello: what's already here. Bluetooth if any (sound
    // gear first), else Osd's output if it's a DAC or known IEMs.
    signal askOutput()
    Timer {
        interval: 5800; running: true
        onTriggered: {
            const audio = ["earbuds", "iem", "headphones", "speaker"];
            const ds = root.connected.slice().sort((a, b) => (audio.indexOf(root.btKind(a)) < 0) - (audio.indexOf(root.btKind(b)) < 0));
            if (!ds.length) { root.askOutput(); return; }
            const c = root.btCard(ds[0]);
            if (ds.length > 1) c.detail = "and " + ds.slice(1).map(d => d.name || "a device").join(", ");
            root.showCard(c, 4200);
        }
    }

    // ── Hello: once per login, and back from the lock ───────────────────
    // Your picture and a greeting. Once per login: the flag lives in the
    // runtime dir, which goes with the session, so a shell restart doesn't
    // greet you again.
    readonly property string face: Quickshell.env("HOME") + "/.face"
    readonly property string userName: { const u = Quickshell.env("USER") || ""; return u.charAt(0).toUpperCase() + u.slice(1); }
    function greeting() {
        const h = new Date().getHours();
        // "Good night" is a goodbye (Farewell says it); arriving late is "Up late".
        return h < 5 ? "Up late" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening";
    }
    FileView {
        id: hello
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice/welcomed"
        printErrors: false
        onLoadFailed: { setText(String(Date.now()) + "\n"); helloLater.start(); }
    }
    // After the desktop has drawn, so it's seen.
    Timer { id: helloLater; interval: 1800; onTriggered: root.show({ kind: "hello", image: root.face, round: true, label: root.greeting(), value: root.userName, ring: -1, tone: Theme.textPrimary }, 3600) }
    // Lock.qml, on the right password: how long you were away.
    function welcomeBack(since) {
        const m = Math.round((Date.now() - since) / 60000);
        const away = m < 1 ? "" : m < 60 ? "away " + m + " min" : "away " + Math.floor(m / 60) + " h " + (m % 60) + " min";
        show({ kind: "hello", image: face, round: true, label: "Welcome back", value: away, ring: -1, tone: Theme.textSecondary }, 2800);
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

    // T3 Code's threads (Notifs, through its adapter): the thread, and how it
    // ended, in the adapter's tone.
    function agentNote(item) {
        const s = String(item.status || "").toLowerCase();
        const tone = item.statusTone;
        const value = tone === "critical" ? "Failed" : /limit/.test(s) ? "Hit a limit"
                    : tone === "caution" ? "Needs you" : "Done";
        const t = String(item.title || item.app);
        show({
            kind: "agent", image: item.icon, glyph: "\u{f06a9}",
            label: t.length > 28 ? t.slice(0, 27).trim() + "…" : t,
            value: value, ring: -1,
            tone: tone === "critical" ? Theme.red : tone === "caution" ? Theme.orange : Theme.green
        }, tone === "caution" || tone === "critical" ? 6000 : 3200);
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
