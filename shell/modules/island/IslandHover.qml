// The island expanded on hover, three columns (after the reference):
//
//   ▣ Kitty                      23:29  Thu, Oct 30                 All caught up 🔔
//   ▮ ▯ ▯ ▯ ▯             ┌ ▧  ROCK IT          ∙∙∙▂▄▆▄∙∙ ┐        [tray]  ▂▄▆ ▭
//                         └    Tokyo Machine              ┘
//
// Where you are (the app, your workspaces), when (a time chip that opens the
// calendar), what's playing (art, song, a waveform that moves with what you
// hear; the controls appear when you hover it), or, with nothing playing,
// how hard the machine works; then notifications and status. Every part is a
// door: the app opens the launcher, the time the calendar, the rings the
// System panel, the bell the notifications.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: hover
    required property var bar
    readonly property var player: bar.player
    readonly property bool media: bar.showMedia
    readonly property var focusWin: Hyprland.activeToplevel
    readonly property var topInfo: focusWin && focusWin.lastIpcObject ? focusWin.lastIpcObject : ({})
    readonly property var app: topInfo.class ? DesktopEntries.heuristicLookup(topInfo.class) : null

    implicitWidth: 720
    implicitHeight: 148

    Component.onCompleted: SystemStats.watch()
    Component.onDestruction: SystemStats.unwatch()

    // ── Left: where ──────────────────────────────────────────────────────
    Column {
        x: 28; y: 24
        width: 200
        spacing: 16
        Row {
            spacing: 8
            Item {
                id: appIcon
                width: 18; height: 18
                anchors.verticalCenter: parent.verticalCenter
                readonly property string path: hover.app && hover.app.icon ? Quickshell.iconPath(hover.app.icon, true) : ""
                IconImage { anchors.fill: parent; visible: appIcon.path !== ""; source: appIcon.path; asynchronous: true }
                Text { visible: appIcon.path === ""; anchors.centerIn: parent; text: "\u{f05b5}"; font.family: Theme.fontGlyph; font.pixelSize: 14; color: Theme.textSecondary }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 170)
                elide: Text.ElideRight
                text: hover.app ? hover.app.name : hover.topInfo.class ? hover.topInfo.class.charAt(0).toUpperCase() + hover.topInfo.class.slice(1) : "Desktop"
                size: 14; weight: Theme.wMedium
            }
            HoverHandler { id: appHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Island.open("launcher", hover.bar.screenName, "pointer", "island") }
        }
        Capsules { bar: hover.bar; scale: 1.1 }
    }
    Item {
        x: 28; y: 24; width: 200; height: 18
        Tip { anchors.horizontalCenter: undefined; x: 0; text: hover.focusWin ? (hover.focusWin.title || "") : ""; shown: appHover.hovered; below: true }
    }

    // ── Centre: when, and what's playing ─────────────────────────────────
    Rectangle {
        id: timeChip
        anchors.horizontalCenter: parent.horizontalCenter
        y: 12
        height: 38; radius: 12
        width: timeRow.implicitWidth + 22
        color: chipHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        Row {
            id: timeRow
            anchors.centerIn: parent
            spacing: 10
            IslandClock {
                now: hover.bar.now; size: 26
                rounded: false; weight: Theme.wMedium
                color: Qt.rgba(1, 0.98, 0.95, 0.95)
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(hover.bar.now, "ddd, MMM d")
                size: 15; weight: Theme.wMedium
                color: Theme.textTertiary
            }
        }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Island.open("calendar", hover.bar.screenName, "pointer", "island") }
    }

    // Now playing
    Rectangle {
        id: card
        visible: hover.media
        anchors.horizontalCenter: parent.horizontalCenter
        y: 62
        width: 380; height: 66; radius: 18
        color: Qt.rgba(1, 1, 1, cardHover.hovered ? 0.07 : 0.045)
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        HoverHandler { id: cardHover }

        ClippingRectangle {
            id: art
            x: 9; anchors.verticalCenter: parent.verticalCenter
            width: 48; height: 48; radius: 11
            color: Qt.rgba(1, 1, 1, 0.08)
            Image { anchors.fill: parent; source: hover.player ? (hover.player.trackArtUrl || "") : ""; sourceSize: Qt.size(96, 96); fillMode: Image.PreserveAspectCrop; asynchronous: true }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.toggleCenter("sound", "pointer") }
        }
        Column {
            anchors { left: art.right; leftMargin: 12; right: trail.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 2
            Label { width: parent.width; elide: Text.ElideRight; text: hover.player ? (hover.player.trackTitle || "Unknown") : ""; size: 14; weight: Theme.wSemibold }
            Label { width: parent.width; elide: Text.ElideRight; text: hover.player ? (hover.player.trackArtist || hover.player.identity || "") : ""; size: 12; color: Theme.textTertiary }
        }

        // The waveform at rest; the controls once the pointer is on the card.
        Item {
            id: trail
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            width: 112; height: 30

            PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
            PwNodePeakMonitor {
                id: peak
                node: Pipewire.defaultAudioSink
                enabled: hover.visible && hover.media && hover.player && hover.player.isPlaying
            }
            readonly property real level: peak.peaks && peak.peaks.length ? Math.max(...peak.peaks) : (peak.peak || 0)
            Row {
                anchors.centerIn: parent
                spacing: 4
                opacity: cardHover.hovered ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                Repeater {
                    model: 13
                    Rectangle {
                        required property int index
                        readonly property real shape: 0.35 + 0.65 * Math.sin(Math.PI * (index + 0.5) / 13)
                        property real jitter: 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; radius: 1.5
                        height: Math.max(3, 24 * Math.min(1, trail.level * shape * jitter * 1.7))
                        color: Theme.accent
                        opacity: 0.9
                        Behavior on height { NumberAnimation { duration: 90 } }
                        Timer { running: peak.enabled && !Theme.reduceMotion; interval: 110 + (index % 4) * 35; repeat: true; onTriggered: parent.jitter = 0.65 + Math.random() * 0.55 }
                    }
                }
            }
            Row {
                anchors.centerIn: parent
                spacing: 4
                opacity: cardHover.hovered ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                Repeater {
                    model: [
                        { g: "\u{f04ae}", on: () => hover.player.previous(), ok: hover.player && hover.player.canGoPrevious },
                        { g: hover.player && hover.player.isPlaying ? "\u{f03e4}" : "\u{f040a}", on: () => hover.player.togglePlaying(), ok: hover.player && hover.player.canTogglePlaying, big: true },
                        { g: "\u{f04ad}", on: () => hover.player.next(), ok: hover.player && hover.player.canGoNext }
                    ]
                    Rectangle {
                        id: tb
                        required property var modelData
                        width: 32; height: 30; radius: 15
                        opacity: modelData.ok ? 1 : 0.35
                        color: tbArea.containsMouse ? Theme.pillHover : "transparent"
                        scale: tbArea.pressed ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                        Text { anchors.centerIn: parent; text: tb.modelData.g; font.family: Theme.fontGlyph; font.pixelSize: tb.modelData.big ? 19 : 15; color: Theme.textPrimary }
                        MouseArea { id: tbArea; anchors.fill: parent; enabled: tb.modelData.ok; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.modelData.on() }
                    }
                }
            }
        }
        // Where in the song
        Rectangle {
            anchors { left: art.right; leftMargin: 12; right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 7 }
            height: 2; radius: 1
            color: Qt.rgba(1, 1, 1, 0.08)
            Rectangle {
                width: parent.width * (hover.player && hover.player.length > 0 ? Math.min(1, hover.player.position / hover.player.length) : 0)
                height: parent.height; radius: 1
                color: Qt.alpha(Theme.accent, 0.8)
            }
            Timer { running: hover.visible && hover.player && hover.player.isPlaying; interval: 1000; repeat: true; onTriggered: hover.player.positionChanged() }
        }
    }

    // Nothing playing: how hard the machine works.
    Row {
        visible: !hover.media
        anchors.horizontalCenter: parent.horizontalCenter
        y: 64
        spacing: 22
        StatRing {
            value: SystemStats.cpu; label: "CPU"; size: 40
            HoverHandler { id: h1 }
            Tip { text: SystemStats.cores.length + " threads · load " + (SystemStats.load.split(" ")[0] || "–"); shown: h1.hovered }
        }
        StatRing {
            value: SystemStats.mem; label: "Memory"; size: 40
            HoverHandler { id: h2 }
            Tip { text: SystemStats.bytes(SystemStats.memUsed) + " of " + SystemStats.bytes(SystemStats.memTotal) + (SystemStats.swapUsed > 1073741824 ? " · swap " + SystemStats.bytes(SystemStats.swapUsed) : ""); shown: h2.hovered }
        }
        StatRing {
            value: SystemStats.gpu; label: "GPU"; size: 40
            text: SystemStats.gpuState === "suspended" ? "off" : Math.round(SystemStats.gpu * 100) + "%"
            HoverHandler { id: h3 }
            Tip { text: SystemStats.gpuState === "suspended" ? "NVIDIA asleep · Intel drives the screens" : "NVIDIA " + SystemStats.gpuTemp + "° · " + Math.round(SystemStats.gpuPower) + " W · Intel " + SystemStats.igpuMHz + " MHz"; shown: h3.hovered }
        }
        StatRing {
            value: Math.min(1, SystemStats.cpuTemp / 100); label: "Temp"; size: 40
            text: SystemStats.cpuTemp ? SystemStats.cpuTemp + "°" : "–"
            color: SystemStats.cpuTemp >= 90 ? Theme.red : SystemStats.cpuTemp >= 80 ? Theme.orange : Theme.green
            HoverHandler { id: h4 }
            Tip { text: "CPU " + SystemStats.cpuTemp + "° · GPU " + SystemStats.gpuTemp + "°" + (SystemStats.fans.length ? " · fans " + SystemStats.fans.join(" / ") + " rpm" : ""); shown: h4.hovered }
        }
        TapHandler { onTapped: Island.open("system", hover.bar.screenName, "pointer", "island") }
    }

    // ── Right: news and status ───────────────────────────────────────────
    Column {
        anchors { right: parent.right; rightMargin: 28 }
        y: 22
        spacing: 16
        Row {
            anchors.right: parent.right
            spacing: 8
            Label { anchors.verticalCenter: parent.verticalCenter; text: Notifs.unread ? Notifs.unread + " new" : "All caught up"; size: 14; weight: Theme.wMedium }
            Text { anchors.verticalCenter: parent.verticalCenter; text: Notifs.dnd ? "\u{f009b}" : "\u{f009a}"; font.family: Theme.fontGlyph; font.pixelSize: 15; color: Notifs.unread ? Theme.accent : Theme.textSecondary }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Notifs.toggleCenter("notifications", "pointer") }
        }
        Row {
            anchors.right: parent.right
            spacing: 14
            TrayRow { window: hover.bar; anchors.verticalCenter: parent.verticalCenter }
            IslandStatus { anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
