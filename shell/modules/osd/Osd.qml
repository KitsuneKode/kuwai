// Glass HUD for brightness, volume and microphone (ported from
// ~/.config/quickshell/glass-osd, now one module of kuwai).
//
// Brightness arrives as events from bin/kuwai-brightness (`watch --part
// osd`), so the HUD shows the requested value on the screen being changed
// before the slow DDC/CI write finishes. Volume and mic are read straight
// from PipeWire, so any change (keys, Waybar scroll, pavucontrol) shows up,
// and the output device is named and drawn by type: earbuds, headphones,
// speaker, display, laptop, with Bluetooth battery when BlueZ reports it.
//
// Motion: critically damped, no overshoot (nothing here is flicked). The
// card drops out from under the bar and leaves back up the same path; the
// level fill chases its target so held keys glide instead of stepping; a
// brightness key pressed at 0/100 stretches the track like a rubber band.
//
// It is also a control: while the pointer rests on it, it stays. Scroll or
// drag the track to set the level, click the glyph to mute (or the mic, or
// Do Not Disturb), click anywhere else to open the full page in the center
// (Sound: outputs, inputs, the microphone; Controls for brightness).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import qs.config
import qs.components.ui
import qs.components
import qs.services
import "state.mjs" as OsdState

Scope {
    id: root

    // ── What the card is showing ─────────────────────────────────────────
    property string glyph: ""
    property string title: ""
    property string subtitle: ""          // shown instead of the track
    property string artImage: ""          // the device's photo (DeviceArt), in place of the glyph
    property string accessoryGlyph: ""
    property string linkGlyph: ""         // how it's attached: Bluetooth or USB
    property string accessory: ""
    property real level: 0                // 0..1
    property string valueText: ""
    property bool muted: false
    property bool showTrack: true
    property string kind: ""              // volume | mic | brightness | dnd
    property string output: ""            // the brightness event's output

    // ── Brightness: event stream from the controller ─────────────────────
    // The shell holds the controller's socket itself (it was a Python relay,
    // `kuwai-brightness watch --part osd`, 13 MB for the shell's life):
    // `kuwai-brightness socket` checks the private directory, starts the
    // controller if needed and says where its socket is; then one line asks
    // for the HUD's events and each event is a line. Held for good: with no
    // HUD subscribed the controller falls back to a notification.
    property string brightnessSock: ""
    Process {
        id: brightnessFind
        running: true
        command: [Paths.bin + "/kuwai-brightness", "socket"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (!p.startsWith("/")) return;
                root.brightnessSock = p;
                brightnessFeed.connected = true;
            }
        }
        onExited: code => { if (code !== 0) feedRestart.start(); }
    }
    Socket {
        id: brightnessFeed
        path: root.brightnessSock
        onConnectedChanged: {
            if (connected) { write('{"action":"watch","part":"osd"}\n'); flush(); }
            else feedRestart.start();               // the controller restarted or went away
        }
        onError: feedRestart.start()
        parser: SplitParser {
            onRead: line => {
                let ev;
                try { ev = JSON.parse(line); } catch (e) { return; }
                if (ev.kind === "brightness") root.showBrightness(ev);
            }
        }
    }
    Timer { id: feedRestart; interval: 2000; onTriggered: if (!brightnessFeed.connected && !brightnessFind.running) brightnessFind.running = true }

    function brightnessGlyph(v) {
        return v === null || v < 34 ? "\u{f00de}" : v < 67 ? "\u{f00df}" : "\u{f00e0}";
    }

    // The center's Sound / Display tab is the control itself: no HUD on top.
    function quietFor(tab) { return Notifs.centerOpen && Notifs.centerTab === tab; }

    function showBrightness(ev) {
        if (quietFor("controls")) return;
        const v = ev.value;
        kind = "brightness";
        output = ev.output || "";
        glyph = brightnessGlyph(v);
        title = ev.label;
        accessoryGlyph = ""; accessory = ""; linkGlyph = "";
        muted = false;
        if (ev.error || v === null) {
            showTrack = false;
            subtitle = ev.error || "Brightness unavailable";
        } else {
            showTrack = true;
            subtitle = "";
            level = v / 100;
            valueText = String(v);
            if (ev.limit) hud.stretch(v >= 100 ? 1 : -1);
        }
        hud.present(ev.output);
    }

    // ── Volume / mic: PipeWire ───────────────────────────────────────────
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    // The device that plays (AudioRoute): the DAC behind EasyEffects, not
    // "Easy Effects Sink". Volume is still the default's (the keys change it).
    readonly property var outNode: AudioRoute.output
    PwObjectTracker { objects: [root.sink, root.source, root.outNode].filter(n => n) }

    // Ignore the burst of property changes while PipeWire binds at startup,
    // and right after the default sink switches (handled as "connected").
    property bool armed: false
    // 3 s: on a cold start (a crash, the lock's restart) nodes bind their
    // properties over a second or two; a USB device read late was "plugged in".
    Timer { running: Pipewire.ready; interval: 3000; onTriggered: { root.armed = true; root.remember(); } }
    property real sinkSwitchedAt: 0

    readonly property real sinkVolume: sink && sink.audio ? sink.audio.volume : -1
    readonly property bool sinkMuted: sink && sink.audio ? sink.audio.muted : false
    readonly property bool micMuted: source && source.audio ? source.audio.muted : false

    // A device being unplugged drops to 0 just before it goes: wait a moment
    // on a fall to 0, and say nothing if the output changed meanwhile.
    onSinkVolumeChanged: {
        const d = OsdState.volumeDecision(root, sinkVolume, Date.now());
        if (d === "holdZero") zeroHold.restart();
        else if (d === "show") showVolume(false);
    }
    Timer { id: zeroHold; interval: OsdState.ZERO_HOLD_MS; onTriggered: if (OsdState.shouldFireZeroHold(root, root.sinkVolume, Date.now())) root.showVolume(false) }
    onSinkMutedChanged: if (OsdState.shouldShowMute(root, Date.now())) showVolume(false)
    onMicMutedChanged: if (armed) showMic()
    onSinkChanged: sinkSwitchedAt = Date.now()
    // The sound moved to another device: the default changed, or EasyEffects
    // was pointed at the other DAC. The default changing to EasyEffects in
    // front of the same DAC is no move.
    readonly property string outName: outNode ? outNode.name : ""
    onOutNameChanged: {
        if (!outName) return;
        sinkSwitchedAt = Date.now();
        leftOut = lastOut;
        if (armed) { sinkTries = 0; sinkConnected.restart(); }
    }
    // The output sound was on, and the one it just left: if that was wired
    // gear and its node is gone, it was unplugged (not just switched away).
    property var lastOut: null        // { name, key, title, glyph, image, wired }
    property var leftOut: null
    function remember() {
        if (!outNode || !sink || !sink.audio) return;
        lastOut = outInfo(outNode);
        Moments.output = lastOut;
    }
    function outInfo(node) {
        const props = node.properties || {};
        const dev = bluetoothDevice(props);
        const bt = props["device.api"] === "bluez5" || !!props["api.bluez5.address"];
        const rawLabel = (dev && dev.name) || props["device.description"] || node.description || "";
        const type = deviceType(rawLabel, props, bt, dev ? (dev.icon || "") : "");
        const art = DeviceArt.lookup(rawLabel) || DeviceArt.lookup(props["device.description"] || "");
        const shownType = art && art.kind && typeGlyph[art.kind] ? art.kind : type;
        return { name: node.name, key: rawLabel.toLowerCase(), title: art ? art.label : sinkLabel(type, props, dev, node),
                 glyph: typeGlyph[shownType], image: art ? art.image : "",
                 // By its bus too: a DAC named like headphones (Audiocular) was
                 // "not wired", so unplugging it said nothing.
                 wired: !bt && (type === "usb" || props["device.bus"] === "usb" || !!art), bt: bt };
    }
    function unplugged(o) {
        return OsdState.isUnplugged(o, outNode ? outNode.name : "", Pipewire.nodes.values.map(n => n.name));
    }
    // Wait for the new node to bind its properties before naming it. A
    // device just plugged in (a DAC) is a new node and can take a few
    // seconds; one already known is ready at the first look.
    property int sinkTries: 0
    Timer {
        id: sinkConnected
        interval: 350; repeat: true
        onTriggered: {
            if (root.sink && root.sink.ready && root.sink.audio && root.outNode && root.outNode.ready) {
                stop();
                const now = Date.now();
                root.sinkSwitchedAt = now;
                const o = root.outInfo(root.outNode);
                const res = OsdState.resolveOutputSwitch({
                    bar: Settings.bar,
                    leftOut: root.leftOut,
                    currentOut: o,
                    currentOutName: root.outNode.name,
                    nodeNames: Pipewire.nodes.values.map(n => n.name),
                    firstSeen: root.firstSeen,
                    now: now,
                    quietSound: root.quietFor("sound")
                });
                if (res.notifyGone) Moments.wiredGone(root.leftOut);
                root.leftOut = null;
                if (res.action === "inputCard")
                    Moments.inputCard({ key: o.key, glyph: o.glyph, image: o.image, title: o.title, link: "usb", gone: false, detail: "Sound is on it" });
                else root.showVolume(true);
            }
            else if (++root.sinkTries > OsdState.MAX_SINK_TRIES) stop();
        }
    }

    // When each device's node first appeared: one that just did was plugged
    // in (or connected); one that's been there was chosen in Sound.
    property var firstSeen: ({})
    // Bound, so their kind and properties are known (a dozen nodes; streams aren't).
    PwObjectTracker { objects: Pipewire.nodes.values.filter(n => !n.isStream) }
    readonly property var deviceNodes: Pipewire.nodes.values.filter(n => !n.isStream && n.audio).map(n => n.name)
    onDeviceNodesChanged: firstSeen = OsdState.updateFirstSeen(firstSeen, deviceNodes, armed, Date.now())
    function fresh(name) { return OsdState.isFreshNode(firstSeen, name, Date.now()); }

    // ── Inputs: a USB microphone (the Boya) plugged in or out, or the
    // input chosen in Sound. Bluetooth headsets' mics come with their card.
    readonly property var externalIns: Pipewire.nodes.values.filter(n => !n.isStream && /^Audio\/Source/.test((n.properties || {})["media.class"] || "")
                                                                     && (n.properties || {})["device.bus"] === "usb")
    property var knownIns: []         // [{ name, key, title, image }]
    onExternalInsChanged: insSettle.restart()
    Timer { id: insSettle; interval: 500; onTriggered: root.diffIns() }
    property real insChangedAt: 0
    // The built-in card's input is whatever is on its port: with something in
    // the 3.5 mm jack (the Boya) that's the jack, and the card ("Built-in
    // Audio Analog Stereo") is not what you're talking into.
    readonly property string jackIn: {
        const j = jackPorts || {};
        if (j["analog-input-mic"] === "available") return Settings.jackMicName || "Jack microphone";
        if (Object.keys(j).some(k => /^analog-input-(headset|headphone)-mic/.test(k) && j[k] === "available")) return "Headset microphone";
        return "";
    }
    function onJack(n) {
        const p = (n && n.properties) || {};
        return jackIn !== "" && (p["device.bus"] === "pci" || p["device.form-factor"] === "internal") && !/hdmi|displayport/i.test(n.name || "");
    }
    function inTitle(n) {
        const p = n.properties || {};
        if (onJack(n)) {
            const jart = DeviceArt.lookup(jackIn);
            return { raw: jackIn, title: jart ? jart.label : jackIn, image: jart ? jart.image : "", jack: true, hasArt: !!jart };
        }
        const raw = p["device.description"] || n.description || n.nickname || n.name || "Microphone";
        const art = DeviceArt.lookup(raw);
        if (!art && p["device.form-factor"] === "internal") return { raw: raw, title: "Built-in Microphone", image: "", hasArt: false };
        return { raw: raw, title: art ? art.label : raw.replace(/ (Analog|Digital|Pro Audio|Multichannel)( (Stereo|Mono|Input|Surround [0-9.]+))?$| (Mono|Stereo)$/, ""),
                 image: art ? art.image : "", hasArt: !!art };
    }
    readonly property string micGlyph: "\u{f036c}"
    readonly property string externalMicGlyph: "\u{f0370}"
    function diffIns() {
        const current = externalIns.map(n => { const t = inTitle(n); return { name: n.name, key: t.raw.toLowerCase(), title: t.title, image: t.image }; });
        const diff = OsdState.diffExternalInputs(knownIns, current, {
            armed: armed,
            bar: Settings.bar,
            now: Date.now(),
            prevChangedAt: insChangedAt,
            externalMicGlyph: externalMicGlyph
        });
        knownIns = diff.knownIns;
        insChangedAt = diff.insChangedAt;
        for (let i = 0; i < diff.baselineKeys.length; i++) Moments.noteDevice(diff.baselineKeys[i], true);
        if (diff.pendingCard) {
            inCard.pending = diff.pendingCard;
            inCard.restart();
        }
    }
    // A moment later: the default input has followed (or not), say which it is.
    Timer {
        id: inCard
        property var pending: null
        interval: 700
        onTriggered: {
            const c = pending; pending = null;
            if (!c) return;
            const src = root.source;
            const resolved = OsdState.resolveInputCard(c, src ? root.inTitle(src) : null);
            if (resolved) Moments.inputCard(resolved);
        }
    }
    // Picked in the center's Sound tab: the list shows it while it's open, so
    // nothing is said then. When it closes, if the output or input you
    // left with isn't the one you came in with, the card says which it is now.
    readonly property bool soundOpen: quietFor("sound")
    property string soundOutWas: ""
    property string soundInWas: ""
    onSoundOpenChanged: {
        if (soundOpen) { soundOutWas = outName; soundInWas = source ? source.name : ""; return; }
        const act = OsdState.resolveSoundClose({
            armed: armed,
            outName: outName,
            soundOutWas: soundOutWas,
            sourceName: source ? source.name : "",
            soundInWas: soundInWas
        });
        if (act === "showVolume") showVolume(true);
        else if (act === "inSwitch") inSwitch.restart();
    }
    // Chosen in Sound (not plugged in or out): which input it is now.
    property string inWas: ""
    onSourceChanged: { if (!armed && source) inWas = source.name; else if (armed && Settings.bar === "island") inSwitch.restart(); }
    Timer {
        id: inSwitch
        interval: 900
        onTriggered: {
            const src = root.source;
            if (!OsdState.shouldAnnounceInputSwitch({
                sourceName: src ? src.name : "",
                inWas: root.inWas,
                now: Date.now(),
                insChangedAt: root.insChangedAt,
                quietSound: root.quietFor("sound")
            })) return;
            root.inWas = src.name;
            const t = root.inTitle(src);
            const ext = (src.properties || {})["device.bus"] === "usb";
            Moments.inputCard({ key: t.raw.toLowerCase(), glyph: ext || t.jack ? root.externalMicGlyph : root.micGlyph, image: t.image,
                                title: t.title, link: ext ? "usb" : t.jack ? "jack" : "", gone: false, quiet: true, detail: "" });
        }
    }

    // Once per login, after hello: a named or external default mic (DeviceArt, USB, Bluetooth)
    // gets the same device card as a wired connect. A plain built-in mic stays quiet.
    property bool loginMicShown: false
    Timer {
        id: loginMic
        interval: 6400
        repeat: false
        running: !root.loginMicShown && root.armed && Moments.freshLogin && Settings.bar === "island"
        onTriggered: {
            root.loginMicShown = true;
            const src = root.source;
            if (!src) return;
            const t = root.inTitle(src);
            const p = src.properties || {};
            const bus = p["device.bus"] || "";
            const raw = t.raw || "";
            const named = !!t.hasArt || /headset|iem/i.test(raw);
            const ext = bus === "usb" || bus === "bluetooth";
            const jack = !!t.jack || /plugged/i.test(raw) || /plugged/i.test(p["port.name"] || "") || /plugged/i.test(src.description || "");
            if (!named && !ext && !jack) return;
            Moments.inputCard({ key: raw.toLowerCase(), glyph: ext ? root.externalMicGlyph : root.micGlyph, image: t.image,
                                title: t.title, link: ext ? bus : (jack ? "jack" : ""), gone: false, quiet: false, detail: "Microphone" });
        }
    }

    // ── The 3.5 mm jack: a mic (the Boya) or headphones plugged in or out.
    // Not a new device, a port on the built-in card becoming available, so
    // the node lists never changed and nothing was said. pactl tells us when
    // the card changes; then the ports' availability is compared.
    property var jackPorts: null        // { "analog-input-mic": "available", … }
    Process {
        id: cardWatch
        running: true
        command: ["setpriv", "--pdeathsig", "KILL", "--", "pactl", "subscribe"]
        stdout: SplitParser { onRead: line => { if (/ on card #/.test(line)) jackCheck.restart(); } }
        onExited: cardRetry.restart()
    }
    Timer { id: cardRetry; interval: 5000; onTriggered: cardWatch.running = true }
    // A change while the list is being read is read again after: unplugging
    // and plugging back in quickly was one read, the second change lost.
    property bool jackAgain: false
    Timer { id: jackCheck; interval: 400; onTriggered: { if (jackList.running) root.jackAgain = true; else jackList.running = true; } }
    Process {
        id: jackList
        running: true
        command: ["pactl", "-f", "json", "list", "cards"]
        stdout: StdioCollector {
            onStreamFinished: {
                let ports = {};
                try {
                    for (const c of JSON.parse(text))
                        for (const [k, v] of Object.entries(c.ports || {}))
                            if (/^analog-(input-(mic|headset-mic|headphone-mic)|output-headphones)/.test(k)) ports[k] = v.availability;
                } catch (e) { return; }
                const before = root.jackPorts;
                root.jackPorts = ports;
                if (root.jackAgain) { root.jackAgain = false; jackCheck.restart(); }
                if (!before || !root.armed) {
                    Moments.noteDevice("jack:mic", ports["analog-input-mic"] === "available");
                    Moments.noteDevice("jack:headphones", ports["analog-output-headphones"] === "available");
                    return;
                }
                if (Settings.bar !== "island") return;
                // One plug, one card. The combo jack can't tell a mic from
                // headphones, so a plug lights its mic and headphone ports
                // together: that said "Wired headphones" and then "Boya".
                // A mic among the changes is the device (it's named, the
                // headphone port is the jack's guess); headphones alone are
                // headphones.
                const changed = Object.keys(ports).filter(k => before[k] !== undefined
                    && (before[k] === "available") !== (ports[k] === "available"));
                if (!changed.length) return;
                const k = changed.find(x => /input/.test(x)) || changed[0];
                const now = ports[k] === "available";
                const mic = /input/.test(k);
                const headset = /headset|headphone-mic/.test(k);
                Moments.inputCard({ key: "jack:" + (mic ? "mic" : "headphones"), glyph: mic ? root.externalMicGlyph : root.typeGlyph.headphones, image: "",
                                    title: mic ? (headset ? "Headset" : (Settings.jackMicName || "Jack microphone")) : "Wired headphones",
                                    link: "jack", gone: !now, detail: mic ? (now ? "Microphone" : "") : "" });
            }
        }
    }

    // ── USB outputs (a DAC) plugged in or out while sound stays where it is;
    // one that takes the sound is told by onSinkChanged.
    readonly property var externalOuts: Pipewire.nodes.values.filter(n => !n.isStream && /^Audio\/Sink/.test((n.properties || {})["media.class"] || "")
                                                                      && (n.properties || {})["device.bus"] === "usb")
    property var knownOuts: []
    onExternalOutsChanged: outsSettle.restart()
    Timer { id: outsSettle; interval: 500; onTriggered: root.diffOuts() }
    function diffOuts() {
        const now = externalOuts.map(n => outInfo(n));
        const added = now.filter(x => !knownOuts.some(k => k.name === x.name));
        const gone = knownOuts.filter(k => !now.some(x => x.name === k.name));
        knownOuts = now;
        if (!armed) { for (const x of now) Moments.noteDevice(x.key, true); return; }
        if (Settings.bar !== "island" || (!added.length && !gone.length)) return;
        outCard.pending = added.length ? Object.assign({}, added[added.length - 1], { gone: false })
                                       : Object.assign({}, gone[gone.length - 1], { gone: true });
        outCard.restart();
    }
    Timer {
        id: outCard
        property var pending: null
        interval: 1500
        onTriggered: {
            const c = pending; pending = null;
            if (!c || !root.outNode || root.outNode.name === c.name || (root.lastOut && root.lastOut.name === c.name)) return;
            const on = root.lastOut ? Moments.short(root.lastOut.title) : "";
            Moments.inputCard({ key: c.key, glyph: c.glyph, image: c.image, title: c.title, link: "usb", gone: c.gone,
                                detail: on ? (c.gone ? "Sound on " : "Sound stays on ") + on : "" });
        }
    }

    function bluetoothDevice(props) {
        const addr = (props["api.bluez5.address"] || "").toUpperCase();
        if (!addr) return null;
        return Bluetooth.devices.values.find(d => d.address.toUpperCase() === addr) || null;
    }

    // BlueZ reports a generic class for most audio gear (both a Sony earbud
    // and a JBL-style speaker say "audio-headset"), so the name decides first.
    function deviceType(label, props, bt, btIcon) {
        const n = label.toLowerCase();
        const ff = props["device.form-factor"] || "";
        const profile = props["device.profile.name"] || "";
        if (bt) {
            if (/buds|pods|\bwf-|earbud|\btws\b|\bear ?\(|liberty|freebuds|elite \d/.test(n)) return "earbuds";
            if (/speaker|boost|\bflip|\bcharge|\bclip|\bgo ?\d|boom|soundlink|soundcore|\bsrs-|soundbar|\becho\b|\bnest\b|\bhome\b/.test(n)) return "speaker";
            if (ff === "speaker" || btIcon.indexOf("speaker") >= 0) return "speaker";
            if (ff === "car") return "car";
            return "headphones";
        }
        if (/hdmi|displayport|iec958/.test(profile) || /\(hdmi\)|displayport/.test(n)) return "display";
        if (ff === "headphones" || ff === "headset") return "headphones";
        if (props["device.bus"] === "usb") return "usb";
        if (ff === "internal") return "laptop";
        return "speaker";
    }

    readonly property var typeGlyph: ({
        earbuds: "\u{f184f}", iem: "\u{f184f}", headphones: "\u{f02cb}", speaker: "\u{f04c3}",
        display: "\u{f0f5f}", laptop: "\u{f0322}", usb: "\u{f0553}", car: "\u{f04c3}"
    })

    // lastIpcObject (which carries the model) is only filled after a refresh.
    Component.onCompleted: Hyprland.refreshMonitors()

    function externalMonitorName() {
        const ext = Hyprland.monitors.values.filter(m => !/^(eDP|LVDS|DSI)-/.test(m.name));
        if (ext.length !== 1) return "";
        const o = ext[0].lastIpcObject || {};
        return o.model || "";
    }

    function sinkLabel(type, props, dev, node) {
        const n = node || outNode || sink;
        if (dev && dev.name) return dev.name;
        if (type === "display") return externalMonitorName() || "Display Audio";
        if (type === "laptop") return "Built-in Speakers";
        return props["device.description"] || (n ? n.nickname || n.description : "") || "Output";
    }

    function batteryGlyph(b) {
        if (b < 0.05) return "\u{f008e}";
        if (b >= 0.95) return "\u{f0079}";
        return String.fromCodePoint(0xf007a + Math.max(0, Math.floor(b * 10) - 1));
    }

    // At login the island asks what's playing sound (Moments).
    Connections {
        target: Moments
        function onAskOutput() { root.showVolume(true, true); }
    }
    function showVolume(connected, boot) {
        if (!sink || !sink.audio || (quietFor("sound") && !boot)) return;
        const out = outNode || sink;
        const props = out.properties || {};
        const dev = bluetoothDevice(props);
        const bt = props["device.api"] === "bluez5" || !!props["api.bluez5.address"];
        const rawLabel = (dev && dev.name) || props["device.description"] || out.description || "";
        const type = deviceType(rawLabel, props, bt, dev ? (dev.icon || "") : "");
        const v = Math.round(sink.audio.volume * 100);

        // What it really is (devices.json): the IEMs behind a DAC, with a photo.
        const art = DeviceArt.lookup(rawLabel) || DeviceArt.lookup(props["device.description"] || "");
        const shownType = art && art.kind && typeGlyph[art.kind] ? art.kind : type;

        // With the island, the sound moving is a card (Moments.card): gear
        // that comes and goes (Bluetooth, a DAC and the IEMs behind it)
        // connects there; anything else just says where sound went.
        const wired = !bt && (type === "usb" || !!art);
        const live = bt || wired;
        remember();
        if (connected && Settings.bar === "island") {
            if (boot && !live) return;
            Moments.outputSwitched({
                key: rawLabel.toLowerCase(), glyph: typeGlyph[shownType], image: art ? art.image : "",
                title: art ? art.label : sinkLabel(type, props, dev), via: art ? art.via : "",
                battery: dev && dev.batteryAvailable ? dev.battery : -1, live: live, boot: !!boot,
                link: bt ? "bluetooth" : wired ? "usb" : "", fresh: !!boot || fresh(out.name),
                level: live ? Math.min(1, v / 100) : -1, muted: sink.audio.muted
            });
            return;
        }
        if (boot) return;
        kind = "volume";
        title = art ? art.label : sinkLabel(type, props, dev);
        muted = sink.audio.muted;
        glyph = muted ? "\u{f075f}" : typeGlyph[shownType];
        artImage = art && !muted ? art.image : "";
        linkGlyph = bt ? "\u{f00af}" : wired ? "\u{f0553}" : "";
        accessoryGlyph = dev && dev.batteryAvailable ? batteryGlyph(dev.battery) : "";
        accessory = dev && dev.batteryAvailable ? Math.round(dev.battery * 100) + "%" : "";
        // Just connected (no island): say so, and through what.
        showTrack = !connected;
        subtitle = connected ? (art && art.via ? "Connected via " + art.via : "Connected") : "";
        level = Math.min(1, v / 100);
        valueText = muted ? "Muted" : String(v);
        hud.present(focusedScreenName());
    }

    function showMic() {
        if (quietFor("sound")) return;
        kind = "mic";
        // Which mic: "Boya Off", not "Microphone Off" (or the card's name).
        const t = source ? inTitle(source) : null;
        const name = t ? t.title : "Microphone";
        title = micMuted ? name + " Off" : name;
        const ext = !!source && ((source.properties || {})["device.bus"] === "usb" || !!t.jack);
        glyph = ext ? (micMuted ? "\u{f0371}" : externalMicGlyph) : (micMuted ? "\u{f036d}" : micGlyph);
        muted = micMuted;
        accessoryGlyph = ""; accessory = ""; linkGlyph = ext ? "\u{f0553}" : "";
        // On: its input level, adjustable like volume. Off: say so.
        showTrack = !micMuted && !!source && !!source.audio;
        subtitle = micMuted ? "Click the microphone to turn it on" : "";
        if (showTrack) {
            level = Math.min(1, source.audio.volume);
            valueText = String(Math.round(source.audio.volume * 100));
        }
        hud.present(focusedScreenName());
    }

    // Do Not Disturb toggled from a shortcut: say so (not while the center is
    // open; its own button shows the state).
    Connections {
        target: Notifs
        function onDndChanged() {
            // With the island as the bar, the island says it (services/Moments).
            if (Notifs.loaded && root.armed && !Notifs.centerOpen && Settings.bar !== "island") root.showDnd();
        }
    }
    function showDnd() {
        kind = "dnd";
        title = Notifs.muted ? "Do Not Disturb" : "Notifications On";
        glyph = Notifs.muted ? "\u{f0594}" : "\u{f009a}";
        muted = false;
        accessoryGlyph = ""; accessory = ""; linkGlyph = "";
        showTrack = false;
        subtitle = Notifs.muted
            ? (Notifs.dndMute && !Notifs.dnd ? "Screen share — only critical alerts" : "Only critical alerts will show")
            : "Alerts will show again";
        hud.present(focusedScreenName());
    }

    function focusedScreenName() {
        return Screens.focusedName;
    }

    // ── Using it ─────────────────────────────────────────────────────────
    // Set the level the card shows (0–1) on whatever it is showing.
    function setLevel(f) {
        f = Math.max(0, Math.min(1, f));
        if (kind === "volume" && sink && sink.audio) {
            sink.audio.volume = f;
            if (sink.audio.muted && f > 0) sink.audio.muted = false;
        } else if (kind === "mic" && source && source.audio) {
            source.audio.volume = f;
            level = f;
            valueText = String(Math.round(f * 100));
        } else if (kind === "brightness" && output) {
            const v = Math.max(1, Math.round(f * 100));
            Display.setBrightness(output, v);
            level = v / 100;
            valueText = String(v);
            glyph = brightnessGlyph(v);
        }
    }
    // A scroll notch: 2% of volume or gain, 5% of brightness.
    function nudge(steps) {
        if (!showTrack) return;
        setLevel(level + steps * (kind === "brightness" ? 0.05 : 0.02));
    }
    function toggleMute() {
        if (kind === "volume" && sink && sink.audio) sink.audio.muted = !sink.audio.muted;
        else if (kind === "mic" && source && source.audio) source.audio.muted = !source.audio.muted;
        else if (kind === "dnd") Notifs.toggleUserDnd();
    }
    function openPage() {
        hud.dismiss();
        Notifs.toggleCenter(kind === "brightness" ? "controls" : kind === "dnd" ? "notifications" : "sound", "pointer", hud.shownScreen ? hud.shownScreen.name : "");
    }

    // ── The HUD surface ──────────────────────────────────────────────────
    PanelWindow {
        id: hud

        property bool mapped: false
        property var shownScreen: Quickshell.screens[0]
        screen: shownScreen
        visible: mapped

        anchors.top: true
        // With the island bar, the HUD is the island growing: same place, same black.
        readonly property bool inIsland: Settings.bar === "island"
        readonly property bool notch: inIsland && Settings.islandStyle !== "floating"
        // The island's own width on this screen: the HUD starts as the island.
        readonly property real islandW: Island.restWidths[shownScreen ? shownScreen.name : ""] || 220
        margins.top: inIsland ? 0 : Theme.barGap
        readonly property real cardW: Math.min(Theme.sp(316), Theme.screenSize(shownScreen, "width", 1920) - 32)
        readonly property real cardH: Math.max(Theme.sp(74), osdCol.implicitHeight + Theme.sp(36))
        implicitWidth: cardW + 32          // fixed: the card morphs inside, the surface never resizes
        implicitHeight: cardH + 36
        // On the island it sits where the island is, not under its reserved strip.
        exclusionMode: inIsland ? ExclusionMode.Ignore : ExclusionMode.Normal
        color: "transparent"

        WlrLayershell.namespace: "kuwai-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Only the card takes the pointer, and only once it's there: the
        // margins stay click-through, and a leaving card is never in the way.
        mask: Region { item: card.reveal > 0.6 ? card : null }

        function present(screenName, hold) {
            linger.interval = hold || 1600;
            // Never a screen that's gone (unplugged, DPMS): the focused one, or any.
            const s = Quickshell.screens.find(x => x.name === screenName)
                || (shownScreen && Quickshell.screens.indexOf(shownScreen) >= 0 ? shownScreen : null)
                || Screens.focused || Quickshell.screens[0];
            if (mapped && s !== shownScreen) {
                // Moving a mapped layer surface recreates it; restart cleanly.
                enter.stop(); leave.stop();
                card.reveal = 0;
                mapped = false;
            }
            shownScreen = s;
            mapped = true;
            leave.stop();
            if (card.reveal < 1 && !enter.running) enter.start();
            if (!cardHover.hovered) linger.restart();
        }

        function dismiss() { linger.stop(); leave.start(); }

        function stretch(direction) {
            trackScale.origin.x = direction > 0 ? 0 : track.width;
            rubber.restart();
        }

        // It answers a keypress, so it's fast and small: 180ms strong
        // ease-out in, 150ms ease-out back up the same 6px path. Both start
        // from the current value, so a re-trigger mid-exit just turns around.
        NumberAnimation { id: enter; target: card; property: "reveal"; to: 1; duration: Theme.hudInMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        NumberAnimation {
            id: leave; target: card; property: "reveal"; to: 0; duration: Theme.hudOutMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut
            onFinished: hud.mapped = false
        }
        Timer { id: linger; interval: 1600; onTriggered: leave.start() }

        GlassCard {
            id: card
            property real reveal: 0
            // In the island it grows out of the pill (≈ its rest size) instead of dropping in.
            width: hud.inIsland ? hud.islandW + (hud.cardW - hud.islandW) * reveal : hud.cardW
            height: hud.inIsland ? 34 + (hud.cardH - 34) * reveal : hud.cardH
            radius: hud.inIsland ? 14 + (30 - 14) * reveal : height / 2.9
            tint: hud.notch ? "transparent" : hud.inIsland ? Qt.rgba(0, 0, 0, 0.9) : Theme.glassTint
            rimColor: hud.notch ? "transparent" : spec.rim
            sheen: hud.notch ? 0 : spec.sheen
            darkRing: hud.notch ? 0 : spec.darkRing
            NotchShape {
                visible: hud.notch
                z: -1
                readonly property real grownT: Math.max(0, Math.min(1, (card.height - 34) / 24))
                x: -ear
                w: card.width
                h: card.height
                ear: 9 + 5 * grownT
                radius: 14 + 16 * grownT
                fill: Qt.rgba(0, 0, 0, 0.94)
                expand: card.reveal
                capH: 34
            }
            x: (hud.width - width) / 2
            y: hud.inIsland ? (hud.notch ? 0 : 6) : 10 - (1 - reveal) * (Theme.reduceMotion ? 0 : 6)
            opacity: hud.inIsland ? Math.min(1, reveal * 4) : Math.min(1, reveal * 1.4)
            // Contents arrive once there's room for them (in the island).
            readonly property real inner: hud.inIsland ? Math.max(0, Math.min(1, (reveal - 0.45) / 0.45)) : 1
            scale: (Theme.reduceMotion ? 1 : 0.97 + 0.03 * reveal) * (cardArea.pressed && !cardArea.dragging ? 0.98 : 1)
            transformOrigin: Item.Top
            Behavior on scale { enabled: !enter.running && !leave.running; NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

            // Resting on it keeps it; leaving lets it go a moment later.
            HoverHandler {
                id: cardHover
                onHoveredChanged: {
                    if (hovered) { linger.stop(); if (leave.running) { leave.stop(); enter.start(); } }
                    else linger.restart();
                }
            }

            // Scroll anywhere on the card; click it for the full page; drag
            // the track (below) to set the level.
            MouseArea {
                id: cardArea
                property bool dragging: false
                property real wheelAcc: 0
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                // Flick it up (or right click) and it goes back into the island
                // at once; a plain click opens the full page.
                property real pressY: 0
                property bool flicked: false
                onPressed: mouse => { pressY = mouse.y; flicked = false; }
                onPositionChanged: mouse => { if (pressed && !dragging && pressY - mouse.y > 16) { flicked = true; hud.dismiss(); } }
                onClicked: mouse => {
                    if (flicked) return;
                    if (mouse.button === Qt.RightButton) hud.dismiss();
                    else root.openPage();
                }
                // Screen readers: the card says the level; press opens the full page.
                Accessible.role: Accessible.Button
                Accessible.name: root.title + (root.valueText ? ", " + root.valueText : "") + (root.muted ? ", muted" : "")
                Accessible.description: "Opens the full page"
                Accessible.onPressAction: root.openPage()
                onWheel: wheel => {
                    const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x;
                    wheelAcc += d;
                    while (Math.abs(wheelAcc) >= 120) {
                        root.nudge(wheelAcc > 0 ? 1 : -1);
                        wheelAcc -= wheelAcc > 0 ? 120 : -120;
                    }
                }
            }

            // Glyph platter
            Rectangle {
                id: platter
                opacity: card.inner
                width: Theme.sp(44); height: width; radius: Theme.r4
                anchors.left: parent.left
                anchors.leftMargin: Theme.sp(15)
                anchors.verticalCenter: parent.verticalCenter
                color: root.kind !== "brightness" && platterArea.containsMouse ? Theme.pillHover : root.muted ? Theme.platterDim : Theme.platter
                scale: platterArea.pressed && !Theme.reduceMotion ? Theme.pressScaleSmall : 1
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                MouseArea {
                    id: platterArea
                    anchors.fill: parent
                    enabled: root.kind !== "brightness"
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleMute()
                }
                Accessible.role: root.kind !== "brightness" ? Accessible.CheckBox : Accessible.Graphic
                Accessible.name: root.kind !== "brightness" ? "Mute " + root.title : root.title
                Accessible.checkable: root.kind !== "brightness"
                Accessible.checked: root.muted
                Accessible.onPressAction: if (root.kind !== "brightness") root.toggleMute()
                Accessible.onToggleAction: if (root.kind !== "brightness") root.toggleMute()

                // The device's photo when there is one (DeviceArt).
                Image {
                    id: artPic
                    anchors.fill: parent
                    anchors.margins: 3
                    visible: root.artImage !== "" && root.kind === "volume" && status === Image.Ready
                    source: root.kind === "volume" ? root.artImage : ""
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true; mipmap: true
                }
                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: !artPic.visible
                    text: root.glyph
                    font.family: Theme.fontGlyph
                    font.pixelSize: Theme.sp(Theme.glyphL)
                    color: root.muted ? Theme.textDim : Theme.textPrimary
                }
            }

            Column {
                id: osdCol
                opacity: card.inner
                anchors.left: platter.right
                anchors.leftMargin: Theme.sp(13)
                anchors.right: parent.right
                anchors.rightMargin: Theme.sp(18)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.sp(9)

                Item {
                    width: parent.width
                    height: titleText.implicitHeight

                    Label {
                        id: titleText
                        anchors.left: parent.left
                        anchors.right: accessoryRow.left
                        anchors.rightMargin: Theme.sp(8)
                        text: root.title
                        elide: Text.ElideRight
                        size: Theme.tBody; weight: Theme.wMedium
                    }

                    // On hover: a chevron says the card opens into its page.
                    Text {
                        id: chevron
                        anchors.right: parent.right
                        anchors.verticalCenter: titleText.verticalCenter
                        text: "\u{f0142}"
                        font.family: Theme.fontGlyph
                        font.pixelSize: Theme.sp(14)
                        color: Theme.textSecondary
                        opacity: cardHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    }

                    Row {
                        id: accessoryRow
                        anchors.right: chevron.left
                        anchors.rightMargin: Theme.sp(4)
                        anchors.verticalCenter: titleText.verticalCenter
                        spacing: Theme.sp(4)
                        Text {
                            textFormat: Text.PlainText
                            visible: root.linkGlyph !== ""
                            text: root.linkGlyph
                            font.family: Theme.fontGlyph
                            font.pixelSize: Theme.sp(14)
                            color: Theme.textSecondary
                        }
                        Text {
                            textFormat: Text.PlainText
                            visible: root.accessoryGlyph !== ""
                            text: root.accessoryGlyph
                            font.family: Theme.fontGlyph
                            font.pixelSize: Theme.sp(14)
                            color: Theme.textSecondary
                        }
                        Label {
                            visible: root.accessory !== ""
                            text: root.accessory
                            size: Theme.tSub; weight: Theme.wMedium; rounded: true; tabular: true
                            color: Theme.textSecondary
                        }
                    }
                }

                Label {
                    visible: !root.showTrack
                    width: parent.width
                    text: root.subtitle
                    elide: Text.ElideRight
                    size: Theme.tSub
                    color: Theme.textSecondary
                }

                Item {
                    visible: root.showTrack
                    width: parent.width
                    height: Theme.sp(12)

                    Item {
                        id: track
                        // A slider for screen readers (value/from/to are what Qt reads), a step per press.
                        readonly property real value: root.level
                        readonly property real from: 0
                        readonly property real to: 1
                        Accessible.role: Accessible.Slider
                        Accessible.name: root.title + (root.valueText ? ", " + root.valueText : "")
                        Accessible.onIncreaseAction: root.nudge(1)
                        Accessible.onDecreaseAction: root.nudge(-1)
                        anchors.left: parent.left
                        anchors.right: valueLabel.left
                        anchors.rightMargin: Theme.sp(10)
                        anchors.verticalCenter: parent.verticalCenter
                        height: Theme.sp(6)
                        transform: Scale { id: trackScale; xScale: 1 }

                        LevelBar {
                            anchors.fill: parent
                            value: root.level
                            glide: !cardArea.dragging
                            dim: root.muted
                        }
                        // Drag (or click) along the track to set the level; the
                        // hit area is taller than the 6px line.
                        MouseArea {
                            anchors.fill: parent
                            anchors.topMargin: -10
                            anchors.bottomMargin: -10
                            cursorShape: Qt.PointingHandCursor
                            preventStealing: true
                            onPressed: mouse => { cardArea.dragging = true; root.setLevel(mouse.x / width); }
                            onPositionChanged: mouse => { if (pressed) root.setLevel(mouse.x / width); }
                            onReleased: cardArea.dragging = false
                            onCanceled: cardArea.dragging = false
                        }
                    }

                    Label {
                        id: valueLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(widest.advanceWidth, current.advanceWidth)
                        horizontalAlignment: Text.AlignRight
                        TextMetrics { id: widest; font: valueLabel.font; text: "100" }
                        TextMetrics { id: current; font: valueLabel.font; text: valueLabel.text }
                        text: root.valueText
                        size: Theme.tSub; weight: Theme.wMedium; rounded: true; tabular: true
                        color: Theme.textSecondary
                    }
                }
            }
        }

        // Rubber band at the boundary: "responsive, but there's nothing more".
        SequentialAnimation {
            id: rubber
            NumberAnimation { target: trackScale; property: "xScale"; to: 1.035; duration: Theme.kickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            NumberAnimation { target: trackScale; property: "xScale"; to: 1.0; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }
    }
}
