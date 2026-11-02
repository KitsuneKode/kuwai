// Glass HUD for brightness, volume and microphone (ported from
// ~/.config/quickshell/glass-osd, now one module of the rice).
//
// Brightness arrives as events from ~/Scripts/brightness.py (`watch --part
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
import qs.components
import qs.services

Scope {
    id: root

    // ── What the card is showing ─────────────────────────────────────────
    property string glyph: ""
    property string title: ""
    property string subtitle: ""          // shown instead of the track
    property string accessoryGlyph: ""
    property string accessory: ""
    property real level: 0                // 0..1 fill
    property string valueText: ""
    property bool muted: false
    property bool showTrack: true
    property string kind: ""              // volume | mic | brightness | dnd
    property string output: ""            // the brightness event's output

    // ── Brightness: event stream from the controller ─────────────────────
    Process {
        id: brightnessFeed
        running: true
        command: [Quickshell.env("HOME") + "/Scripts/brightness.sh", "watch", "--part", "osd"]
        stdout: SplitParser {
            onRead: line => {
                let ev;
                try { ev = JSON.parse(line); } catch (e) { return; }
                if (ev.kind === "brightness") root.showBrightness(ev);
            }
        }
        onExited: feedRestart.start()
    }
    Timer { id: feedRestart; interval: 2000; onTriggered: brightnessFeed.running = true }

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
        accessoryGlyph = ""; accessory = "";
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
    PwObjectTracker { objects: [root.sink, root.source] }

    // Ignore the burst of property changes while PipeWire binds at startup,
    // and right after the default sink switches (handled as "connected").
    property bool armed: false
    Timer { running: Pipewire.ready; interval: 1500; onTriggered: root.armed = true }
    property real sinkSwitchedAt: 0

    readonly property real sinkVolume: sink && sink.audio ? sink.audio.volume : -1
    readonly property bool sinkMuted: sink && sink.audio ? sink.audio.muted : false
    readonly property bool micMuted: source && source.audio ? source.audio.muted : false

    onSinkVolumeChanged: if (armed && sinkVolume >= 0 && Date.now() - sinkSwitchedAt > 600) showVolume(false)
    onSinkMutedChanged: if (armed && Date.now() - sinkSwitchedAt > 600) showVolume(false)
    onMicMutedChanged: if (armed) showMic()
    onSinkChanged: {
        sinkSwitchedAt = Date.now();
        if (armed) sinkConnected.restart();
    }
    // Wait for the new node to bind its properties before naming it.
    Timer { id: sinkConnected; interval: 350; onTriggered: if (root.sink && root.sink.ready) root.showVolume(true) }

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
        earbuds: "\u{f184f}", headphones: "\u{f02cb}", speaker: "\u{f04c3}",
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

    function sinkLabel(type, props, dev) {
        if (dev && dev.name) return dev.name;
        if (type === "display") return externalMonitorName() || "Display Audio";
        if (type === "laptop") return "Built-in Speakers";
        return props["device.description"] || sink.nickname || sink.description || "Output";
    }

    function batteryGlyph(b) {
        if (b < 0.05) return "\u{f008e}";
        if (b >= 0.95) return "\u{f0079}";
        return String.fromCodePoint(0xf007a + Math.max(0, Math.floor(b * 10) - 1));
    }

    function showVolume(connected) {
        if (!sink || !sink.audio || quietFor("sound")) return;
        const props = sink.properties || {};
        const dev = bluetoothDevice(props);
        const bt = props["device.api"] === "bluez5" || !!props["api.bluez5.address"];
        const rawLabel = (dev && dev.name) || props["device.description"] || sink.description || "";
        const type = deviceType(rawLabel, props, bt, dev ? (dev.icon || "") : "");
        const v = Math.round(sink.audio.volume * 100);

        kind = "volume";
        title = sinkLabel(type, props, dev);
        muted = sink.audio.muted;
        glyph = muted ? "\u{f075f}" : typeGlyph[type];
        if (dev && dev.batteryAvailable) {
            accessoryGlyph = batteryGlyph(dev.battery);
            accessory = Math.round(dev.battery * 100) + "%";
        } else {
            accessoryGlyph = bt ? "\u{f00af}" : "";
            accessory = "";
        }
        showTrack = true;
        subtitle = "";
        level = Math.min(1, v / 100);
        valueText = muted ? "Muted" : String(v);
        hud.present(focusedScreenName());
    }

    function showMic() {
        if (quietFor("sound")) return;
        kind = "mic";
        title = micMuted ? "Microphone Off" : (source ? (source.description || "Microphone") : "Microphone");
        glyph = micMuted ? "\u{f036d}" : "\u{f036c}";
        muted = micMuted;
        accessoryGlyph = ""; accessory = "";
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
            if (Notifs.loaded && root.armed && !Notifs.centerOpen) root.showDnd();
        }
    }
    function showDnd() {
        kind = "dnd";
        title = Notifs.dnd ? "Do Not Disturb" : "Notifications On";
        glyph = Notifs.dnd ? "\u{f0594}" : "\u{f009a}";
        muted = false;
        accessoryGlyph = ""; accessory = "";
        showTrack = false;
        subtitle = Notifs.dnd ? "Only critical alerts will show" : "Alerts will show again";
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
        else if (kind === "dnd") Notifs.dnd = !Notifs.dnd;
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
        implicitWidth: 316 + 32          // fixed: the card morphs inside, the surface never resizes
        implicitHeight: 74 + 36
        // On the island it sits where the island is, not under its reserved strip.
        exclusionMode: inIsland ? ExclusionMode.Ignore : ExclusionMode.Normal
        color: "transparent"

        WlrLayershell.namespace: "rice-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Only the card takes the pointer, and only once it's there: the
        // margins stay click-through, and a leaving card is never in the way.
        mask: Region { item: card.reveal > 0.6 ? card : null }

        function present(screenName) {
            const s = Quickshell.screens.find(x => x.name === screenName) || shownScreen;
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
            width: hud.inIsland ? hud.islandW + (316 - hud.islandW) * reveal : 316
            height: hud.inIsland ? 34 + (74 - 34) * reveal : 74
            radius: hud.inIsland ? 14 + (30 - 14) * reveal : height / 2.9
            tint: hud.inIsland ? Qt.rgba(0, 0, 0, 0.9) : Theme.glassTint
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
                width: 44; height: 44; radius: 22
                anchors.left: parent.left
                anchors.leftMargin: 15
                anchors.verticalCenter: parent.verticalCenter
                color: root.kind !== "brightness" && platterArea.containsMouse ? Theme.pillHover : root.muted ? Theme.platterDim : Theme.platter
                scale: platterArea.pressed ? 0.94 : 1
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

                Text {
                    anchors.centerIn: parent
                    text: root.glyph
                    font.family: Theme.fontGlyph
                    font.pixelSize: 22
                    color: root.muted ? Theme.textDim : Theme.textPrimary
                }
            }

            Column {
                opacity: card.inner
                anchors.left: platter.right
                anchors.leftMargin: 13
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9

                Item {
                    width: parent.width
                    height: titleText.implicitHeight

                    Text {
                        id: titleText
                        anchors.left: parent.left
                        anchors.right: accessoryRow.left
                        anchors.rightMargin: 8
                        text: root.title
                        elide: Text.ElideRight
                        font.family: Theme.fontText
                        font.weight: Theme.wMedium
                        font.pixelSize: 14
                        font.variableAxes: ({ "opsz": Theme.opszFor(14), "wght": Theme.wMedium })
                        font.letterSpacing: Theme.tracking(14, false)
                        renderType: Text.NativeRendering
                        color: Theme.textPrimary
                    }

                    // On hover: a chevron says the card opens into its page.
                    Text {
                        id: chevron
                        anchors.right: parent.right
                        anchors.verticalCenter: titleText.verticalCenter
                        text: "\u{f0142}"
                        font.family: Theme.fontGlyph
                        font.pixelSize: 14
                        color: Theme.textSecondary
                        opacity: cardHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    }

                    Row {
                        id: accessoryRow
                        anchors.right: chevron.opacity > 0 ? chevron.left : parent.right
                        anchors.rightMargin: chevron.opacity > 0 ? 4 : 0
                        anchors.verticalCenter: titleText.verticalCenter
                        spacing: 4
                        Text {
                            visible: root.accessoryGlyph !== ""
                            text: root.accessoryGlyph
                            font.family: Theme.fontGlyph
                            font.pixelSize: 14
                            color: Theme.textSecondary
                        }
                        Text {
                            visible: root.accessory !== ""
                            text: root.accessory
                            // Numerals in SF Pro Rounded, as Control Center sets them
                            font.family: Theme.fontRounded
                            font.weight: Theme.wMedium
                            font.pixelSize: 13
                            font.letterSpacing: Theme.tracking(13, true)
                            renderType: Text.NativeRendering
                            font.features: { "tnum": 1 }
                            color: Theme.textSecondary
                        }
                    }
                }

                Text {
                    visible: !root.showTrack
                    width: parent.width
                    text: root.subtitle
                    elide: Text.ElideRight
                    font.family: Theme.fontText
                    font.pixelSize: 13
                    font.variableAxes: ({ "opsz": Theme.opszFor(13), "wght": Theme.wRegular })
                    font.letterSpacing: Theme.tracking(13, false)
                    renderType: Text.NativeRendering
                    color: Theme.textSecondary
                }

                Item {
                    visible: root.showTrack
                    width: parent.width
                    height: 12

                    Item {
                        id: track
                        anchors.left: parent.left
                        anchors.right: valueLabel.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        height: 6
                        transform: Scale { id: trackScale; xScale: 1 }

                        Rectangle {
                            anchors.fill: parent
                            radius: 3
                            color: Theme.track
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
                        Rectangle {
                            id: fill
                            property real shown: root.level
                            // The fill chases its target from wherever it is,
                            // so held keys glide instead of stepping.
                            // A dragging pointer is followed 1:1.
                            Behavior on shown { enabled: !cardArea.dragging; NumberAnimation { duration: Theme.glideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                            width: Math.max(height, parent.width * Math.max(0, Math.min(1, shown)))
                            visible: shown > 0.004
                            height: parent.height
                            radius: 3
                            color: root.muted ? Theme.fillDim : Theme.fill
                            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                        }
                    }

                    Text {
                        id: valueLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        // Reserve room for "100" so the track length never jitters.
                        width: Math.max(widest.advanceWidth, current.advanceWidth)
                        horizontalAlignment: Text.AlignRight
                        TextMetrics { id: widest; font: valueLabel.font; text: "100" }
                        TextMetrics { id: current; font: valueLabel.font; text: valueLabel.text }
                        text: root.valueText
                        font.family: Theme.fontRounded
                        font.weight: Theme.wMedium
                        font.pixelSize: 13
                        font.letterSpacing: Theme.tracking(13, true)
                        renderType: Text.NativeRendering
                        font.features: { "tnum": 1 }
                        color: Theme.textSecondary
                    }
                }
            }
        }

        // Rubber band at the boundary: "responsive, but there's nothing more".
        SequentialAnimation {
            id: rubber
            NumberAnimation { target: trackScale; property: "xScale"; to: 1.035; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: trackScale; property: "xScale"; to: 1.0; duration: 320; easing.type: Easing.OutCubic }
        }
    }
}
