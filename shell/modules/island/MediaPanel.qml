// Now Playing, grown out of the island (Apple's expanded music activity):
//
//   [art]  Title                         ▂▅▃▆▄   ← live, in the art's colour
//          Artist · App
//   1:24  ━━━━━━━━━━━●────────────  −1:34       ← drag or click to seek
//   ⤨      ⏮      ⏯      ⏭      ↻      🎧
//
// Shuffle and repeat show only when the player supports them; the last
// button is where it plays (the Sound tab: outputs, per-app). The art and
// title take you to the player. Keys: Space play/pause, ← → ±10 s (⇧ ±30 s),
// N / P next / previous, S shuffle, R repeat, L the player's own action
// (♥ in Cider, copy link in a web player: bin/rice-player), Esc closes.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.config
import qs.components
import qs.services

FocusScope {
    id: np
    focus: true
    implicitWidth: 440
    implicitHeight: 212

    readonly property var p: Media.active
    readonly property color tint: Media.artColor
    Component.onCompleted: Media.watch()
    Component.onDestruction: Media.unwatch()

    function nudge(s) { if (p && p.canSeek && Media.length > 0) Media.seekTo((Media.position + s) / Media.length); }
    Keys.onPressed: event => {
        const k = event.key, shift = event.modifiers & Qt.ShiftModifier;
        if (!p) return;
        if (k === Qt.Key_Space) p.togglePlaying();
        else if (k === Qt.Key_Right) nudge(shift ? 30 : 10);
        else if (k === Qt.Key_Left) nudge(shift ? -30 : -10);
        else if (k === Qt.Key_N && p.canGoNext) p.next();
        else if (k === Qt.Key_P && p.canGoPrevious) p.previous();
        else if (k === Qt.Key_S && p.shuffleSupported) p.shuffle = !p.shuffle;
        else if (k === Qt.Key_R && p.loopSupported) np.cycleLoop();
        else if (k === Qt.Key_L && np.kind !== "") np.contextAct();
        else return;
        event.accepted = true;
    }
    // ── What this player can do beyond MPRIS (bin/rice-player) ──────────
    // Cider: Love (Apple Music rating). A web player that tells us its page
    // (Chromium-family browsers do; Firefox/Zen don't): copy the link, at
    // this second for YouTube. Anything else: no extra button.
    readonly property string pageUrl: {
        const m = p && p.metadata ? p.metadata : null;
        const u = m ? String(m["xesam:url"] || "") : "";
        return /^https?:\/\//.test(u) ? u : "";
    }
    readonly property string kind: !p ? "" : /cider/i.test(p.identity || "") ? "cider" : pageUrl ? "link" : ""
    readonly property bool youtube: /youtube\.com\/watch|youtu\.be\//.test(pageUrl)
    property var loved: ({})                       // this session: track → loved
    readonly property string trackKey: p ? (p.trackTitle || "") + "|" + (p.trackArtist || "") : ""
    readonly property bool isLoved: !!loved[trackKey]
    property string note: ""                       // a short answer in the subtitle line
    Timer { id: noteFor; interval: 2600; onTriggered: np.note = "" }
    function say(t) { note = t; noteFor.restart(); }
    Process {
        id: act
        property var onOk: null
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            if (code === 0) { if (act.onOk) act.onOk(); }
            else np.say((actErr.text || "Didn't work").trim().split("\n").pop());
        }
    }
    function run(args, ok) { if (act.running) return; act.onOk = ok; act.command = [Quickshell.shellDir + "/../bin/rice-player", ...args]; act.running = true; }
    function contextAct() {
        if (kind === "cider") {
            const key = trackKey, was = isLoved;
            run(["cider", was ? "unlove" : "love"], () => {
                const l = Object.assign({}, np.loved); l[key] = !was; np.loved = l;
                np.say(was ? "Removed love" : "Loved");
            });
        } else if (kind === "link") {
            const at = youtube ? Math.floor(Media.position) : 0;
            run(["link", pageUrl, String(at)], () => np.say(at > 0 ? "Link copied at " + Media.clock(at) : "Link copied"));
        }
    }
    function cycleLoop() {
        p.loopState = p.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                    : p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
    }

    // Nothing to play.
    Label {
        visible: !np.p
        anchors.centerIn: parent
        text: "Nothing playing"
        size: 14; color: Theme.textTertiary
    }

    Item {
        visible: !!np.p
        anchors { fill: parent; margins: 22 }

        // ── Art, title, live waveform ────────────────────────────────────
        ClippingRectangle {
            id: art
            width: 64; height: 64; radius: 14
            color: Qt.rgba(1, 1, 1, 0.08)
            Image { anchors.fill: parent; source: Media.art; sourceSize: Qt.size(128, 128); fillMode: Image.PreserveAspectCrop; asynchronous: true }
            Text { visible: !Media.art; anchors.centerIn: parent; text: "\u{f075a}"; font.family: Theme.fontGlyph; font.pixelSize: 26; color: Theme.textTertiary }
            scale: artArea.pressed ? 0.96 : 1
            Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        }
        Column {
            id: titles
            anchors { left: art.right; leftMargin: 14; right: ctx.visible ? ctx.left : wave.left; rightMargin: 12; verticalCenter: art.verticalCenter }
            spacing: 3
            Label { width: parent.width; elide: Text.ElideRight; text: np.p ? (np.p.trackTitle || "Unknown") : ""; size: 16; weight: Theme.wSemibold }
            Label {
                width: parent.width; elide: Text.ElideRight
                text: np.note !== "" ? np.note : np.p ? [np.p.trackArtist, np.p.identity].filter(x => x).join(" · ") : ""
                size: 13; color: np.note !== "" ? np.tint : Theme.textSecondary
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            }
        }
        MouseArea {
            id: artArea
            anchors { left: art.left; right: titles.right; top: art.top; bottom: art.bottom }
            cursorShape: Qt.PointingHandCursor
            onClicked: { Media.goTo(); Island.close(); }
        }
        Tip { anchors.horizontalCenter: undefined; x: 0; text: "Go to " + (np.p ? np.p.identity : "the player"); shown: artArea.containsMouse; below: true }

        // The player's own action: ♥ for Cider, a link for web players.
        Item {
            id: ctx
            visible: np.kind !== ""
            anchors { right: wave.left; rightMargin: 8; verticalCenter: art.verticalCenter }
            width: 34; height: 34
            Rectangle {
                anchors.fill: parent; radius: width / 2
                color: ctxArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : np.isLoved && np.kind === "cider" ? Qt.alpha(np.tint, 0.18) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            }
            Text {
                anchors.centerIn: parent
                text: np.kind === "cider" ? (np.isLoved ? "\u{f02d1}" : "\u{f02d5}") : "\u{f0337}"
                font.family: Theme.fontGlyph; font.pixelSize: 17
                color: np.kind === "cider" && np.isLoved ? np.tint : Theme.textPrimary
                opacity: act.running ? 0.5 : 1
                scale: ctxArea.pressed ? 0.86 : 1
                Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            }
            MouseArea { id: ctxArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: np.contextAct() }
            Tip {
                text: np.kind === "cider" ? (np.isLoved ? "Loved · click to undo" : "Love this song (Apple Music)")
                    : np.youtube ? "Copy link at " + Media.clock(Media.position) : "Copy link"
                shown: ctxArea.containsMouse; below: true
            }
        }

        // Live level of what's playing, in the art's colour; flat while paused.
        Item {
            id: wave
            anchors { right: parent.right; verticalCenter: art.verticalCenter }
            width: 40; height: 24
            PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
            PwNodePeakMonitor { id: peak; node: Pipewire.defaultAudioSink; enabled: Media.playing }
            readonly property real level: peak.enabled ? (peak.peaks && peak.peaks.length ? Math.max(...peak.peaks) : (peak.peak || 0)) : 0
            Row {
                anchors.centerIn: parent
                spacing: 3
                Repeater {
                    model: 6
                    Rectangle {
                        required property int index
                        readonly property real shape: [0.45, 0.8, 1, 0.7, 0.9, 0.5][index]
                        property real jitter: 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; radius: 1.5
                        readonly property real liveH: Math.max(3, 22 * Math.min(1, wave.level * shape * jitter * 1.8))
                        readonly property real pauseH: Math.max(4, 20 * shape * 0.45)
                        height: Media.playing ? liveH : pauseH
                        color: np.tint
                        opacity: Media.playing ? 1 : 0.55
                        Behavior on height { NumberAnimation { duration: Media.playing ? 90 : 380; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
                        Behavior on color { ColorAnimation { duration: 400 } }
                        Timer { running: Media.playing && !Theme.reduceMotion; interval: 120 + (index % 3) * 40; repeat: true; onTriggered: parent.jitter = 0.7 + Math.random() * 0.5 }
                    }
                }
            }
        }

        // ── Time and scrubber ────────────────────────────────────────────
        Item {
            id: scrub
            anchors { left: parent.left; right: parent.right; top: art.bottom; topMargin: 18 }
            height: 18
            readonly property bool can: !!np.p && np.p.canSeek && Media.length > 0
            // While dragging, the knob follows you; the player seeks on release.
            property real dragF: -1
            readonly property real f: dragF >= 0 ? dragF : Media.fraction
            Label {
                id: elapsed
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: 44
                text: Media.clock(scrub.f * Media.length)
                size: 11; color: Theme.textTertiary
                font.features: ({ "tnum": 1 })
            }
            Label {
                id: remain
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 44; horizontalAlignment: Text.AlignRight
                text: Media.length > 0 ? "−" + Media.clock(Media.length - scrub.f * Media.length) : ""
                size: 11; color: Theme.textTertiary
                font.features: ({ "tnum": 1 })
            }
            Item {
                id: track
                anchors { left: elapsed.right; right: remain.left; leftMargin: 6; rightMargin: 6; verticalCenter: parent.verticalCenter }
                height: 18
                readonly property bool active: trackArea.containsMouse || trackArea.pressed
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: track.active ? 8 : 5; radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.14)
                    Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Rectangle {
                        width: parent.width * scrub.f
                        height: parent.height; radius: parent.radius
                        color: track.active ? np.tint : Qt.rgba(1, 1, 1, 0.85)
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                }
                MouseArea {
                    id: trackArea
                    anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
                    enabled: scrub.can
                    hoverEnabled: true
                    cursorShape: scrub.can ? Qt.PointingHandCursor : Qt.ArrowCursor
                    preventStealing: true
                    function at(x) { return Math.max(0, Math.min(1, x / width)); }
                    onPressed: mouse => scrub.dragF = at(mouse.x)
                    onPositionChanged: mouse => { if (pressed) scrub.dragF = at(mouse.x); }
                    onReleased: mouse => { Media.seekTo(at(mouse.x)); release.restart(); }
                    onCanceled: scrub.dragF = -1
                }
                // Hold the dropped spot until the player reports its new position.
                Timer { id: release; interval: 350; onTriggered: scrub.dragF = -1 }
            }
        }

        // ── Controls ─────────────────────────────────────────────────────
        Row {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            spacing: 18
            Repeater {
                model: [
                    { g: "\u{f049d}", tip: "Shuffle", show: !!np.p && np.p.shuffleSupported, on: !!np.p && np.p.shuffle, act: () => np.p.shuffle = !np.p.shuffle, ok: !!np.p && np.p.canControl },
                    { g: "\u{f04ae}", tip: "Previous", show: true, act: () => np.p.previous(), ok: !!np.p && np.p.canGoPrevious, size: 24 },
                    { g: np.p && np.p.isPlaying ? "\u{f03e4}" : "\u{f040a}", tip: np.p && np.p.isPlaying ? "Pause" : "Play", show: true, act: () => np.p.togglePlaying(), ok: !!np.p && np.p.canTogglePlaying, size: 32, big: true },
                    { g: "\u{f04ad}", tip: "Next", show: true, act: () => np.p.next(), ok: !!np.p && np.p.canGoNext, size: 24 },
                    { g: np.p && np.p.loopState === MprisLoopState.Track ? "\u{f0458}" : "\u{f0456}", tip: np.p && np.p.loopState === MprisLoopState.Track ? "Repeat one" : "Repeat", show: !!np.p && np.p.loopSupported,
                      on: !!np.p && np.p.loopState !== MprisLoopState.None, act: () => np.cycleLoop(), ok: !!np.p && np.p.canControl },
                    { g: "\u{f02cb}", tip: "Plays on " + (Pipewire.defaultAudioSink ? (Pipewire.defaultAudioSink.nickname || Pipewire.defaultAudioSink.description) : "…"), show: true,
                      act: () => { Island.close(); Notifs.toggleCenter("sound", "pointer", Island.screen); }, ok: true }
                ].filter(b => b.show)
                Item {
                    id: btn
                    required property var modelData
                    width: modelData.big ? 48 : 36; height: 48
                    opacity: modelData.ok ? 1 : 0.3
                    Rectangle {
                        anchors.centerIn: parent
                        width: btn.modelData.big ? 48 : 34; height: width; radius: width / 2
                        color: btnArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : btn.modelData.on ? Qt.alpha(np.tint, 0.18) : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: btn.modelData.g
                        font.family: Theme.fontGlyph
                        font.pixelSize: btn.modelData.size || 17
                        color: btn.modelData.on ? np.tint : Theme.textPrimary
                        scale: btnArea.pressed ? 0.86 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    }
                    // Shuffle / repeat on: a dot under it (Apple's).
                    Rectangle {
                        visible: !!btn.modelData.on
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 4 }
                        width: 4; height: 4; radius: 2
                        color: np.tint
                    }
                    MouseArea { id: btnArea; anchors.fill: parent; enabled: btn.modelData.ok; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.modelData.act() }
                    Tip { text: btn.modelData.tip; shown: btnArea.containsMouse; below: true }
                }
            }
        }
    }
}
