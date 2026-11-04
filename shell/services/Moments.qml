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
import Quickshell.Hyprland
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
    //   card: { key, glyph, image, title, state, tone, detail, battery (0..1 or -1), gone, link, quiet, open }
    //   link: "bluetooth" | "usb" | "", a badge on the device
    //   quiet: chosen, not connected (an output picked in Sound): no link ring
    //   open: what a click does (Sound in the center if unset)
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
                 detail: art && art.via ? "via " + art.via : "", battery: d.batteryAvailable ? d.battery : -1, gone: false,
                 link: "bluetooth" };
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
            if (["earbuds", "iem", "headphones", "speaker"].indexOf(root.btKind(ds[ds.length - 1])) >= 0) { stays.key = c.key; stays.restart(); }
        }
    }
    // Sound gear connected while sound stays elsewhere (the IEMs still
    // plugged in): say where it is, once the sound has had time to move.
    Timer {
        id: stays
        property string key: ""
        interval: 2500
        onTriggered: {
            if (!root.card || root.card.key !== key || !root.output || root.output.key === key) return;
            root.showCard(Object.assign({}, root.card, { detail: "Sound stays on " + root.short(root.output.title) }), 3000);
        }
    }
    property var lastGone: null
    // Osd: the output sound is on now ({ key, title, wired, bt, … }).
    property var output: null
    function deviceGone(g) {
        const art = DeviceArt.lookup(g.name);
        lastGone = { key: g.name.toLowerCase(), at: Date.now(), output: true };
        showCard({ key: lastGone.key, glyph: kindGlyph[g.kind], image: art ? art.image : "", title: art ? art.label : g.name,
                   state: "Disconnected", tone: Theme.textSecondary, detail: "", battery: -1, gone: true, link: "bluetooth" }, 3400);
    }
    // Osd, when wired gear (a DAC, the IEMs behind it) is unplugged:
    // { key, glyph, image, title }. Then outputSwitched says where sound went.
    function wiredGone(o) {
        lastGone = { key: o.key, at: Date.now(), output: true };
        showCard({ key: o.key, glyph: o.glyph, image: o.image, title: o.title,
                   state: "Disconnected", tone: Theme.textSecondary, detail: "", battery: -1, gone: true, link: "usb" }, 3400);
    }
    // Osd, when the sound moves: { key, glyph, image, title, via, battery, live, boot }.
    // `live`: a device that comes and goes (Bluetooth, USB, a known DAC).
    function outputSwitched(o) {
        // Headphones just went: say where the sound went instead.
        if (lastGone && lastGone.output && Date.now() - lastGone.at < 4000 && card && card.gone && lastGone.key !== o.key) {
            showCard(Object.assign({}, card, { detail: "Sound on " + short(o.title) }), 3400);
            return;
        }
        // Plugged in or just connected: "Connected". Already there, picked
        // in Sound: which output it is now, quietly.
        const linked = o.live && o.fresh;
        showCard({ key: o.key, glyph: o.glyph, image: o.image, title: o.title,
                   state: linked ? "Connected" : "Sound output", tone: linked ? Theme.green : Theme.textSecondary,
                   detail: o.via ? "via " + o.via : "", battery: o.battery, gone: false, link: o.link || "", quiet: !linked,
                   level: linked ? o.level : -1, muted: !!o.muted }, linked ? 4800 : 2600);
    }
    // Osd, for inputs: a USB microphone plugged in or out, or the input
    // picked in Sound (quiet): { key, glyph, image, title, link, gone, quiet, detail }.
    // "Sony WF-C510" → "WF-C510", "Kiwi Ears Cadenza" → "Cadenza": the maker
    // goes where a detail line is short of room; a name that is the model
    // ("AirPods Pro", "Galaxy Buds 2") stays whole.
    readonly property var makers: ["Kiwi Ears", "Audio-Technica", "Sennheiser", "Soundcore", "Moondrop", "Truthear", "Samsung", "OnePlus",
                                   "Xiaomi", "Nothing", "Google", "Realme", "Anker", "Jabra", "Apple", "Beats", "Sony", "Bose", "FiiO", "JBL", "7Hz", "BOYA"]
    function short(t) {
        t = t || "";
        for (const m of makers) if (t.toLowerCase().startsWith(m.toLowerCase() + " ") && t.length > m.length + 1) return t.slice(m.length + 1);
        return t;
    }
    function inputCard(c) {
        if (c.gone) lastGone = { key: c.key, at: Date.now() };
        showCard({ key: c.key, glyph: c.glyph, image: c.image, title: c.title, link: c.link, gone: c.gone, quiet: !!c.quiet,
                   state: c.gone ? "Disconnected" : c.quiet ? "Sound input" : "Connected",
                   tone: c.gone || c.quiet ? Theme.textSecondary : Theme.green, detail: c.detail || "", battery: -1 },
                 c.gone ? 3400 : c.quiet ? 2600 : 4000);
    }
    // Once per login, after the hello: what's already here. Bluetooth if any
    // (sound gear first), else Osd's output if it's a DAC or known IEMs. A
    // shell restart in the session already knows.
    signal askOutput()
    Timer {
        interval: 5800; running: true
        onTriggered: {
            if (!root.freshLogin) return;
            const audio = ["earbuds", "iem", "headphones", "speaker"];
            const ds = root.connected.slice().sort((a, b) => (audio.indexOf(root.btKind(a)) < 0) - (audio.indexOf(root.btKind(b)) < 0));
            // The gear sound is on comes first (the IEMs, though the earbuds
            // are connected too); then Bluetooth, sound gear first.
            const out = root.output;
            if (!ds.length || (out && (out.wired || out.bt))) { root.askOutput(); return; }
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
        onLoadFailed: { root.freshLogin = true; setText(String(Date.now()) + "\n"); helloLater.start(); }
    }
    // Settled: the greeting and the first look at what's here are over, and
    // news that can wait (updates) may come. A fresh login gets a minute to
    // breathe; a shell restart in the session, less.
    property bool freshLogin: false
    property bool settled: false
    Timer { interval: root.freshLogin ? 60000 : 20000; running: !root.settled; onTriggered: root.settled = true }
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

    // ── Power: the charger in and out, and charged ───────────────────────
    // A card like a device's: the plug, what it's doing, the charge as its
    // ring. Plugged in but holding (a charge limit): it says so, not
    // "Charging". The estimate comes a few seconds after, and fills in.
    property bool wasOnBattery: UPower.onBattery
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            if (UPower.onBattery === root.wasOnBattery) return;
            root.wasOnBattery = UPower.onBattery;
            if (!root.armed || !root.battery || !root.battery.isLaptopBattery) return;
            powerSettle.restart();
        }
    }
    function duration(secs) {
        const m = Math.round(secs / 60);
        return m < 60 ? m + " min" : Math.floor(m / 60) + " h" + (m % 60 ? " " + (m % 60) + " min" : "");
    }
    function powerCard() {
        const b = root.battery;
        const on = !UPower.onBattery;
        const holding = on && (b.state === UPowerDeviceState.PendingCharge || b.state === UPowerDeviceState.FullyCharged);
        const est = on ? (b.timeToFull > 0 ? "Full in " + duration(b.timeToFull) : "") : (b.timeToEmpty > 0 ? duration(b.timeToEmpty) + " left" : "");
        return { key: "power", glyph: on ? "\u{f06a5}" : "\u{f06a6}", image: "", link: "", battery: root.pct / 100,
                 title: !on ? "On Battery" : holding ? (b.state === UPowerDeviceState.FullyCharged ? "Fully Charged" : "Plugged In") : "Charging",
                 state: on ? "Connected" : "Disconnected", tone: on ? Theme.green : Theme.textSecondary, gone: !on,
                 detail: holding ? "Running on power, battery at rest" : est,
                 open: () => Island.open("power", Screens.focusedName, "pointer", "island") };
    }
    // A charger that flickers (a loose plug) says so once, not every time:
    // a second change within 20 s only updates a card still showing.
    property real powerToldAt: 0
    Timer {
        id: powerSettle; interval: 700
        onTriggered: {
            const showing = root.card && root.card.key === "power";
            if (!showing && Date.now() - root.powerToldAt < 20000) return;
            root.powerToldAt = Date.now();
            root.toldDone = !UPower.onBattery && root.holding();
            root.showCard(root.powerCard(), 4000);
            powerEstimate.restart();
        }
    }
    Timer { id: powerEstimate; interval: 3500; onTriggered: if (root.card && root.card.key === "power") root.showCard(root.powerCard(), 3000) }
    // Done charging, once each time it's plugged in: to the full, or to the
    // charge limit (it then runs on power, the battery left alone).
    property bool toldDone: false
    function holding() { return !!battery && (battery.state === UPowerDeviceState.PendingCharge || battery.state === UPowerDeviceState.FullyCharged); }
    readonly property int powerState: battery ? battery.state : 0
    onPowerStateChanged: {
        if (UPower.onBattery) { toldDone = false; return; }
        if (!armed || toldDone || powerSettle.running || !holding() || !battery.isLaptopBattery) return;
        toldDone = true;
        const full = powerState === UPowerDeviceState.FullyCharged;
        showCard(Object.assign(powerCard(), full ? { title: "Fully Charged", state: "Charged", detail: "Running on power" }
                                                 : { title: "Charge Limit Reached", state: "Charged", detail: "Held at " + pct + "%, running on power" }), 4500);
    }

    // ── Displays: one plugged in or out ──────────────────────────────────
    // Its model and its mode; Hyprland fills those in a moment after.
    property var displays: ({})       // name → title
    function displayTitle(name) {
        const m = Hyprland.monitors.values.find(x => x.name === name);
        const o = m ? m.lastIpcObject || {} : {};
        const model = /^0x[0-9a-f]+$/i.test(o.model || "") ? "" : o.model;
        return { title: /^(eDP|LVDS|DSI)-/.test(name) ? "Built-in Display" : model || o.description || name,
                 detail: o.width ? o.width + " × " + o.height + (o.refreshRate ? " · " + Math.round(o.refreshRate) + " Hz" : "") : "" };
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "monitoraddedv2") {
                const name = String(event.data).split(",")[1] || "";
                if (!name || /^HEADLESS|^FALLBACK/.test(name)) return;
                displayAdded.names = displayAdded.names.concat([name]);
                Hyprland.refreshMonitors();
                displayAdded.restart();
            } else if (event.name === "monitorremovedv2" || event.name === "monitorremoved") {
                const name = event.name === "monitorremovedv2" ? String(event.data).split(",")[1] : String(event.data);
                const t = root.displays[name];
                if (!t || !root.armed) return;
                root.lastGone = { key: "display:" + name, at: Date.now() };
                root.showCard({ key: "display:" + name, glyph: "\u{f0379}", image: "", title: t, state: "Disconnected",
                                tone: Theme.textSecondary, detail: "", battery: -1, gone: true, link: "" }, 3400);
            }
        }
    }
    Timer {
        id: displayAdded
        property var names: []
        interval: 600
        onTriggered: {
            const name = names[names.length - 1];
            names = [];
            const t = root.displayTitle(name);
            const d = Object.assign({}, root.displays); d[name] = t.title; root.displays = d;
            if (!root.armed) return;
            root.showCard({ key: "display:" + name, glyph: "\u{f0379}", image: "", title: t.title, state: "Connected",
                            tone: Theme.green, detail: t.detail, battery: -1, gone: false, link: "",
                            open: () => Notifs.toggleCenter("controls", "pointer", Screens.focusedName) }, 4000);
        }
    }
    Component.onCompleted: {
        Hyprland.refreshMonitors();
        const d = {};
        for (const m of Hyprland.monitors.values) d[m.name] = displayTitle(m.name).title;
        displays = d;
    }

    // ── Drives: a USB stick or disk plugged in or out ───────────────────
    // udev says something changed; lsblk says what's there. Pulled out
    // while still mounted: it says so, in orange.
    property var drives: []           // [{ path, title, size, removable, mounted }]
    property bool drivesKnown: false
    Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=block"]
        stdout: SplitParser { onRead: line => { if (/ (add|remove) /.test(line)) drivesLater.restart(); } }
    }
    Timer { id: drivesLater; interval: 1200; onTriggered: if (!lsblk.running) lsblk.running = true }
    Timer { interval: 2000; running: true; onTriggered: lsblk.running = true }
    function bytes(n) {
        const gb = n / 1e9;
        return gb >= 1000 ? (gb / 1000).toFixed(gb >= 10000 ? 0 : 1) + " TB" : gb >= 1 ? Math.round(gb) + " GB" : Math.round(n / 1e6) + " MB";
    }
    Process {
        id: lsblk
        command: ["lsblk", "-J", "-b", "-o", "PATH,TYPE,TRAN,HOTPLUG,RM,SIZE,LABEL,MODEL,VENDOR,MOUNTPOINTS"]
        stdout: StdioCollector {
            onStreamFinished: {
                let devs = [];
                try { devs = JSON.parse(text).blockdevices || []; } catch (e) { return; }
                const now = devs.filter(d => d.type === "disk" && d.tran === "usb" && d.hotplug).map(d => {
                    const parts = d.children || [];
                    const label = (parts.find(p => p.label) || {}).label || "";
                    const name = [d.vendor, d.model].filter(x => x && x.trim()).map(x => x.trim()).join(" ");
                    const mounts = parts.concat([d]).flatMap(p => (p.mountpoints || []).filter(m => m));
                    return { path: d.path, title: label || name || "USB Drive", size: root.bytes(d.size),
                             removable: !!d.rm, mounted: mounts.length > 0, part: (parts[0] || d).path };
                });
                const was = root.drives;
                root.drives = now;
                if (!root.drivesKnown) { root.drivesKnown = true; return; }
                if (!root.armed) return;
                const added = now.filter(x => !was.some(w => w.path === x.path));
                const gone = was.filter(w => !now.some(x => x.path === w.path));
                const glyph = d => d.removable ? "\u{f129e}" : "\u{f02ca}";
                if (added.length) {
                    const d = added[added.length - 1];
                    root.showCard({ key: "drive:" + d.path, glyph: glyph(d), image: "", title: d.title, state: "Connected",
                                    tone: Theme.green, detail: d.size, battery: -1, gone: false, link: "usb",
                                    open: () => root.openDrive(d.part) }, 4000);
                } else if (gone.length) {
                    const d = gone[gone.length - 1];
                    root.lastGone = { key: "drive:" + d.path, at: Date.now() };
                    root.showCard({ key: "drive:" + d.path, glyph: glyph(d), image: "", title: d.title,
                                    state: "Disconnected", tone: d.mounted ? Theme.orange : Theme.textSecondary,
                                    detail: d.mounted ? "Removed without ejecting" : "", battery: -1, gone: true, link: "usb" }, d.mounted ? 5000 : 3400);
                }
            }
        }
    }
    // Mounted already (an automounter), or mount it now; then the files.
    function openDrive(dev) {
        Quickshell.execDetached(["sh", "-c", 'm=$(lsblk -nro MOUNTPOINT "$1" | head -n1); [ -n "$m" ] || m=$(udisksctl mount -b "$1" | sed -n "s/.* at //p"); [ -n "$m" ] && xdg-open "$m"', "sh", dev]);
    }

    // ── Network: the connection coming and going ─────────────────────────
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
