// The center's Sound tab: a mixer.
//
//   [Mic] [App] [App] …                           │ [Master] │
//    fader + live stereo meter, dB, mute (M)        framed, pinned right
//    each strip in its own colour, its level as a percentage, and (apps)
//    which output it plays to: click to send it somewhere else
//   Output   every device: pick the default, set its own volume
//   Input    the same for microphones
//
// Faders are the Fluid Functionalism slider standing up: glued to the
// pointer while dragged, sprung on a click, wheel to step. Levels come from
// PipeWire's own peak monitor (PwNodePeakMonitor), only while visible.
// Volume is PipeWire's (cubic) linear value; dB = 60·log10(v), 100% = 0 dB.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import qs.config
import qs.components
import qs.services

Item {
    id: view

    required property var center
    property bool hosting: true
    readonly property bool shown: hosting && center.open && center.tab === "sound"

    function key(event, queryEmpty) { return false; }
    function reset() { strips.contentX = 0; routeFor = null; }
    function selectFirst() {}
    function back() { if (!routeFor) return false; routeFor = null; return true; }

    // The app whose output picker is open (null: none).
    property var routeFor: null
    property Item routeAnchor: null
    property var routeCurrent: null            // where that app plays now
    function route(stream, sink) {
        const serial = stream.properties["object.serial"];
        if (serial && sink) runner.createObject(view, { command: ["pactl", "move-sink-input", String(serial), sink.name] }).running = true;
        routeFor = null;
    }
    Component { id: runner; Process { onExited: destroy() } }

    // Colour by what the stream is: music pink, browsers blue, calls indigo,
    // games purple, system sounds teal; anything else a stable pick.
    function tintFor(n, title) {
        const s = ((n && n.properties ? (n.properties["application.process.binary"] || "") + " " + (n.properties["application.name"] || "") + " " + (n.properties["media.role"] || "") : "") + " " + (title || "")).toLowerCase();
        if (/spotify|music|mpv|vlc|rhythmbox|amberol|cider|tidal|youtube music|elisa|lollypop|mpd/.test(s)) return "#ff375f";
        if (/firefox|zen|chrom|brave|vivaldi|edge|librewolf|epiphany|browser/.test(s)) return Theme.blue;
        if (/discord|vesktop|slack|zoom|teams|telegram|signal|whatsapp|webcord|phone|communication/.test(s)) return Theme.indigo;
        if (/steam|game|wine|proton|lutris|heroic|minecraft/.test(s)) return Theme.focus;
        if (/notif|event|speech|canberra|alert|voxtype|dunst|sound/.test(s)) return Theme.cyan;
        const palette = [Theme.cyan, "#30d158", "#ff9f0a", "#ffd60a", "#ac8e68", "#66d4cf"];
        let h = 0;
        for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
        return palette[Math.abs(h) % palette.length];
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var all: Pipewire.nodes.values
    // By node type, which PipeWire tells before a node is bound. (Its
    // properties come only once bound, and only listed nodes get bound: the
    // old media.class filter left most outputs and every app out for good.)
    readonly property var apps: all.filter(n => n.type === PwNodeType.AudioOutStream && center.matchesText(appName(n)))
    readonly property var allSinks: all.filter(n => n.type === PwNodeType.AudioSink)
    readonly property var sinks: allSinks.filter(n => center.matchesText(deviceName(n)))
    readonly property var sources: all.filter(n => n.type === PwNodeType.AudioSource && center.matchesText(deviceName(n)))

    PwObjectTracker { objects: [view.sink, view.source, ...view.apps, ...view.allSinks, ...view.sources].filter(n => n) }

    function dB(v) {
        if (!(v > 0.0005)) return "−∞";
        const d = 60 * Math.log10(v);
        return (d > 0.05 ? "+" : d < -0.05 ? "−" : "") + Math.abs(d).toFixed(1) + " dB";
    }
    function appName(n) {
        const p = n.properties || {};
        const raw = p["application.name"] || p["media.name"] || n.description || n.name || "App";
        // ALSA apps (voxtype…) all arrive as "ALSA plug-in [binary]": use the binary.
        const alsa = /^ALSA plug-in \[(.+)\]$/.exec(raw);
        const bin = alsa ? alsa[1] : "";
        return bin ? bin.charAt(0).toUpperCase() + bin.slice(1) : raw;
    }
    function appIcon(n) {
        const p = n.properties || {};
        const own = p["application.icon-name"] ? Quickshell.iconPath(p["application.icon-name"], true) : "";
        return own || NotifAdapters.iconForApp(appName(n)) || "";
    }
    function deviceName(n) {
        return n ? (n.nickname || n.description || n.name) : "";
    }

    readonly property real naturalHeight: body.implicitHeight + 8
    Flickable {
        anchors.fill: parent
        clip: true
        contentHeight: body.implicitHeight + 8
        boundsBehavior: Flickable.DragAndOvershootBounds

        Column {
            id: body
            width: parent.width
            spacing: 22

            // ── Now Playing ──────────────────────────────────────────────
            NowPlaying {
                visible: player !== null
                opacity: view.center.revealAt(60)
            }

            // ── Strips ───────────────────────────────────────────────────
            Item {
                width: parent.width
                height: 318
                opacity: view.center.revealAt(80)

                Flickable {
                    id: strips
                    anchors { left: parent.left; right: masterCard.left; rightMargin: 10; top: parent.top; bottom: parent.bottom }
                    clip: true
                    contentWidth: stripRow.implicitWidth
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.DragAndOvershootBounds

                    Row {
                        id: stripRow
                        height: parent.height
                        spacing: 6
                        Strip {
                            node: view.source
                            title: "Mic"
                            glyph: "\u{f036c}"
                            // Orange means "recording now" (the island's dot too).
                            tint: Activities.micInUse ? Theme.orange : "white"
                            caption: view.deviceName(view.source)
                        }
                        Repeater {
                            model: ScriptModel { values: view.apps }
                            Strip {
                                required property var modelData
                                node: modelData
                                title: view.appName(modelData)
                                icon: view.appIcon(modelData)
                                glyph: "\u{f075a}"
                                tint: view.tintFor(modelData, title)
                                routable: true
                            }
                        }
                    }
                }

                // Master: framed and pinned, like a desk's master section.
                Rectangle {
                    id: masterCard
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 84
                    radius: 18
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    Strip {
                        anchors.centerIn: parent
                        node: view.sink
                        title: "Master"
                        glyph: "\u{f057e}"
                        tint: "white"
                        caption: view.deviceName(view.sink)
                    }
                }
            }

            // ── Devices ──────────────────────────────────────────────────
            DeviceList {
                view: view
                title: "Output"
                glyph: "\u{f04c3}"
                nodes: view.sinks
                current: view.sink
                onPicked: n => Pipewire.preferredDefaultAudioSink = n
                opacity: view.center.revealAt(120)
            }
            DeviceList {
                view: view
                title: "Input"
                glyph: "\u{f036c}"
                nodes: view.sources
                current: view.source
                onPicked: n => Pipewire.preferredDefaultAudioSource = n
                opacity: view.center.revealAt(150)
            }
        }
    }

    // ── Pieces ───────────────────────────────────────────────────────────
    // The playing player (else the first one): art, track, artist, controls,
    // and a scrubber you can seek with when the player allows it.
    component NowPlaying: Rectangle {
        id: np
        readonly property var player: Mpris.players.values.find(p => p.playbackState === MprisPlaybackState.Playing)
            || Mpris.players.values[0] || null
        width: parent ? parent.width : 0
        height: 132
        radius: 18
        color: Qt.rgba(1, 1, 1, 0.065)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.06)

        // MPRIS doesn't push position; ask while playing and on screen.
        Timer {
            running: np.player && np.player.isPlaying && view.shown
            interval: 500
            repeat: true
            onTriggered: np.player.positionChanged()
        }
        function clock(s) {
            s = Math.max(0, Math.floor(s || 0));
            return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
        }

        ClippingRectangle {
            id: art
            x: 12; y: 12
            width: 64; height: 64
            radius: 12
            color: Theme.platter
            Image {
                anchors.fill: parent
                source: np.player ? np.player.trackArtUrl : ""
                sourceSize: Qt.size(128, 128)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Text {
                anchors.centerIn: parent
                visible: !(np.player && np.player.trackArtUrl)
                text: "\u{f075a}"
                font.family: Theme.fontGlyph
                font.pixelSize: 24
                color: Theme.textTertiary
            }
        }
        Column {
            anchors { left: art.right; leftMargin: 12; right: controls.left; rightMargin: 8; top: art.top; topMargin: 6 }
            spacing: 3
            Label { width: parent.width; elide: Text.ElideRight; text: np.player ? (np.player.trackTitle || "Unknown track") : ""; size: 14; weight: Theme.wSemibold }
            Label { width: parent.width; elide: Text.ElideRight; text: np.player ? (np.player.trackArtist || np.player.identity || "") : ""; size: 12; color: Theme.textSecondary }
            Label { width: parent.width; elide: Text.ElideRight; text: np.player ? (np.player.identity || "") : ""; size: 11; color: Theme.textTertiary }
        }
        Row {
            id: controls
            anchors { right: parent.right; rightMargin: 10; verticalCenter: art.verticalCenter }
            spacing: 2
            Repeater {
                model: [
                    { g: "\u{f04ae}", act: "prev", big: false },
                    { g: np.player && np.player.isPlaying ? "\u{f03e4}" : "\u{f040a}", act: "toggle", big: true },
                    { g: "\u{f04ad}", act: "next", big: false }
                ]
                Rectangle {
                    id: btn
                    required property var modelData
                    width: modelData.big ? 40 : 32; height: width; radius: width / 2
                    color: btnArea.containsMouse ? Theme.pillHover : modelData.big ? Theme.pill : "transparent"
                    scale: btnArea.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Text {
                        anchors.centerIn: parent
                        text: btn.modelData.g
                        font.family: Theme.fontGlyph
                        font.pixelSize: btn.modelData.big ? 20 : 16
                        color: Theme.textPrimary
                    }
                    MouseArea {
                        id: btnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const p = np.player;
                            if (!p) return;
                            if (btn.modelData.act === "toggle" && p.canTogglePlaying) p.togglePlaying();
                            else if (btn.modelData.act === "next" && p.canGoNext) p.next();
                            else if (btn.modelData.act === "prev" && p.canGoPrevious) p.previous();
                        }
                    }
                }
            }
        }
        Slider {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
            height: 28
            enabled: np.player && np.player.canSeek && np.player.length > 0
            from: 0
            to: np.player && np.player.length > 0 ? np.player.length : 1
            stepSize: 1
            value: np.player ? np.player.position : 0
            label: np.clock(np.player ? np.player.position : 0)
            valueText: np.player && np.player.length > 0 ? "−" + np.clock(np.player.length - np.player.position) : ""
            onMoved: v => { if (np.player && np.player.canSeek) np.player.position = v; }
        }
    }

    component Strip: Item {
        id: strip
        property var node: null
        property string title
        property string glyph
        property string icon
        property color tint: Theme.blue
        property string caption              // under the name: the device (Mic, Master)
        property bool routable: false        // app streams: which output, and a picker
        readonly property var audio: node && node.audio ? node.audio : null
        // Where an app plays: the sink its links lead to.
        PwNodeLinkTracker { id: links; node: strip.routable ? strip.node : null }
        readonly property var target: {
            const g = (links.linkGroups || []).find(l => l.target && !l.target.isStream);
            return g ? g.target : null;
        }
        readonly property real vol: audio ? audio.volume : 0
        readonly property bool muted: audio ? audio.muted : false

        width: 76
        height: 318

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            spacing: 6

            // Icon tile
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 32; height: 32; radius: 10
                color: Qt.alpha(strip.tint, 0.20)
                border.width: 1
                border.color: Qt.alpha(strip.tint, 0.28)
                ClippingRectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 6
                    color: "transparent"
                    visible: strip.icon !== "" && appImg.status === Image.Ready
                    Image { id: appImg; anchors.fill: parent; source: strip.icon; sourceSize: Qt.size(48, 48); smooth: true; mipmap: true }
                }
                Text {
                    anchors.centerIn: parent
                    visible: !(strip.icon !== "" && appImg.status === Image.Ready)
                    text: strip.glyph
                    font.family: Theme.fontGlyph
                    font.pixelSize: 15
                    color: strip.tint
                }
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 68
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: strip.title
                size: 12
                weight: Theme.wSemibold
            }
            // The device it plays to (apps: a picker), or what it is.
            Rectangle {
                id: routeChip
                anchors.horizontalCenter: parent.horizontalCenter
                width: 70; height: 18; radius: 9
                color: strip.routable && routeArea.containsMouse ? Theme.pillHover : strip.routable ? Theme.pill : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                Label {
                    anchors.centerIn: parent
                    width: parent.width - 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    // No link seen yet (it follows the default output): name that, not "—".
                    text: strip.routable ? view.deviceName(strip.target || view.sink) + " \u25BE" : strip.caption
                    size: 11
                    color: Theme.textTertiary
                }
                MouseArea {
                    id: routeArea
                    anchors.fill: parent
                    enabled: strip.routable
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        view.routeAnchor = routeChip;
                        view.routeCurrent = strip.target;
                        view.routeFor = view.routeFor === strip.node ? null : strip.node;
                    }
                }
            }

            // Fader + meter
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                LevelMeter {
                    node: strip.node
                    active: view.shown && !strip.muted
                    width: 10
                    height: 150
                }
                Slider {
                    vertical: true
                    width: 34
                    height: 150
                    value: strip.vol
                    dim: strip.muted
                    fillColor: Qt.alpha(strip.tint, strip.tint === Qt.color("white") ? 0.30 : 0.62)
                    onMoved: v => { if (strip.audio) strip.audio.volume = v; }
                    onRightClicked: if (strip.audio) strip.audio.muted = !strip.audio.muted
                }
            }

            // Level: the percentage people read, the dB engineers do.
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 0
                RollingNumber {
                    anchors.horizontalCenter: parent.horizontalCenter
                    value: strip.vol * 100
                    suffix: "%"
                    size: 13
                    weight: Theme.wSemibold
                    color: strip.muted ? Theme.textTertiary : Theme.textPrimary
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: strip.audio ? view.dB(strip.vol) : ""
                    size: 10
                    rounded: true
                    font.features: ({ "tnum": 1 })
                    color: Theme.textTertiary
                }
            }

            // Mute
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 30; height: 22; radius: 11
                color: strip.muted ? Qt.alpha(Theme.red, 0.85) : muteArea.containsMouse ? Theme.pillHover : Theme.pill
                scale: muteArea.pressed ? 0.94 : 1
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                Label {
                    anchors.centerIn: parent
                    text: "M"
                    size: 11
                    rounded: true
                    weight: Theme.wSemibold
                    color: strip.muted ? "white" : Theme.textSecondary
                }
                MouseArea {
                    id: muteArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: view.center.tip(parent, containsMouse, strip.muted ? "Unmute " + strip.title : "Mute " + strip.title + "  (or right-click the fader)")
                    onClicked: if (strip.audio) strip.audio.muted = !strip.audio.muted
                }
            }
        }
    }

    // ── The output picker for one app (opened from its strip) ─────────────
    MouseArea {
        anchors.fill: parent
        visible: view.routeFor !== null
        onClicked: view.routeFor = null
    }
    Rectangle {
        id: routeMenu
        readonly property var stream: view.routeFor
        readonly property point at: view.routeAnchor && stream ? view.routeAnchor.mapToItem(view, 0, view.routeAnchor.height + 6) : Qt.point(0, 0)
        visible: opacity > 0.01
        opacity: stream ? 1 : 0
        scale: stream || Theme.reduceMotion ? 1 : 0.96
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: routeMenu.stream ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        Behavior on scale { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        x: Math.max(0, Math.min(view.width - width, at.x + (view.routeAnchor ? view.routeAnchor.width / 2 : 0) - width / 2))
        y: Math.min(view.height - height, at.y)
        width: 240
        height: menuCol.implicitHeight + 12
        radius: 14
        color: Qt.rgba(0.17, 0.17, 0.20, 0.98)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        z: 20
        Column {
            id: menuCol
            x: 6; y: 6
            width: parent.width - 12
            Label { x: 8; height: 24; verticalAlignment: Text.AlignVCenter; text: "Play on"; size: 11; weight: Theme.wSemibold; color: Theme.textTertiary }
            Repeater {
                model: view.allSinks
                Rectangle {
                    id: opt
                    required property var modelData
                    readonly property bool on: view.routeCurrent === modelData
                    width: menuCol.width
                    height: 32
                    radius: 9
                    color: optArea.containsMouse ? Qt.alpha(Theme.blue, 0.85) : "transparent"
                    Text {
                        id: tick
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: opt.on ? "\u{f012c}" : ""
                        width: 16
                        font.family: Theme.fontGlyph
                        font.pixelSize: 13
                        color: Theme.textPrimary
                    }
                    Label {
                        anchors { left: tick.right; leftMargin: 6; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight
                        text: view.deviceName(opt.modelData)
                        size: 13
                        weight: opt.on ? Theme.wSemibold : Theme.wRegular
                    }
                    MouseArea {
                        id: optArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.route(view.routeFor, opt.modelData)
                    }
                }
            }
        }
    }
}
