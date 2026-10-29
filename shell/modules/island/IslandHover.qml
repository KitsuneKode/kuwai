// The island expanded on hover: three rows, each with one job.
//
//   ▣ Kitty                                        ☁ 24°   🔔 1 new
//     T3code notification improvement
//
//   23:29              ┌ ▧  Rock It                 ⏮  ⏯  ⏭ ┐
//   Thursday, 29 Oct   └    Tokyo Machine    ━━━━━━━━──────── ┘
//                      (nothing playing: CPU · RAM · GPU rings)
//
//   ● ▮ ● ● ●                                  [tray]   ▂▄▆  87% ⚡
//
// Where you are (app and window), when (clock and date), what's playing (or
// how hard the machine works), then the workspaces and the tray. Every part
// is a door: the app row opens the launcher, the clock the calendar, the
// bell the notifications, the rings the System panel, the battery the
// controls.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
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
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery && battery.isLaptopBattery && battery.isPresent
    readonly property int pct: hasBattery ? Math.round(battery.percentage > 1 ? battery.percentage : battery.percentage * 100) : 0
    readonly property bool charging: hasBattery && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged)

    implicitWidth: 600
    implicitHeight: 182

    // Stats are read only while this is on screen.
    Component.onCompleted: SystemStats.watch()
    Component.onDestruction: SystemStats.unwatch()

    // ── Where ────────────────────────────────────────────────────────────
    Item {
        id: rowA
        x: 22; y: 18
        width: parent.width - 44; height: 34

        Item {
            id: appIcon
            width: 30; height: 30
            anchors.verticalCenter: parent.verticalCenter
            readonly property string path: hover.app && hover.app.icon ? Quickshell.iconPath(hover.app.icon, true) : ""
            IconImage { anchors.fill: parent; visible: appIcon.path !== ""; source: appIcon.path; asynchronous: true }
            Rectangle {
                visible: appIcon.path === ""
                anchors.fill: parent; radius: 8; color: Theme.pill
                Text { anchors.centerIn: parent; text: "\u{f05b5}"; font.family: Theme.fontGlyph; font.pixelSize: 16; color: Theme.textSecondary }
            }
        }
        Column {
            anchors { left: appIcon.right; leftMargin: 10; right: right.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 0
            Label { width: parent.width; elide: Text.ElideRight; text: hover.app ? hover.app.name : (hover.topInfo.class || "Desktop"); size: 13; weight: Theme.wSemibold }
            Label { width: parent.width; elide: Text.ElideRight; text: hover.focusWin ? (hover.focusWin.title || "") : "Workspace " + hover.bar.activeWs; size: 11; color: Theme.textTertiary }
        }
        MouseArea {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: right.left }
            cursorShape: Qt.PointingHandCursor
            onClicked: Island.open("launcher", hover.bar.screenName, "pointer")
        }

        Row {
            id: right
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8
            Chip {
                visible: SystemStats.weatherTemp !== ""
                glyph: SystemStats.weatherGlyph
                text: SystemStats.weatherTemp
                tip: SystemStats.weatherText
            }
            Chip {
                glyph: Notifs.dnd ? "\u{f009b}" : "\u{f009a}"
                text: Notifs.unread ? Notifs.unread + " new" : "All caught up"
                tint: Notifs.unread ? Theme.accent : "transparent"
                onClicked: Notifs.toggleCenter("notifications", "pointer")
            }
        }
    }

    // ── When, and what's playing ─────────────────────────────────────────
    Item {
        id: rowB
        x: 22; y: 66
        width: parent.width - 44; height: 62

        Column {
            id: when
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            IslandClock { now: hover.bar.now; size: 38 }
            Label { text: Qt.formatDate(hover.bar.now, "dddd, d MMMM"); size: 12; color: Theme.textTertiary }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Island.open("calendar", hover.bar.screenName, "pointer") }
        }

        // Now playing
        Rectangle {
            visible: hover.media
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 330; height: 62; radius: 16
            color: Qt.rgba(1, 1, 1, 0.06)
            ClippingRectangle {
                id: art
                x: 8; anchors.verticalCenter: parent.verticalCenter
                width: 46; height: 46; radius: 10
                color: Qt.rgba(1, 1, 1, 0.08)
                Image { anchors.fill: parent; source: hover.player ? (hover.player.trackArtUrl || "") : ""; sourceSize: Qt.size(92, 92); fillMode: Image.PreserveAspectCrop; asynchronous: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.toggleCenter("sound", "pointer") }
            }
            Column {
                anchors { left: art.right; leftMargin: 10; right: transport.left; rightMargin: 8; top: art.top; topMargin: 2 }
                spacing: 1
                Label { width: parent.width; elide: Text.ElideRight; text: hover.player ? (hover.player.trackTitle || "Unknown") : ""; size: 13; weight: Theme.wSemibold }
                Label { width: parent.width; elide: Text.ElideRight; text: hover.player ? (hover.player.trackArtist || hover.player.identity || "") : ""; size: 11; color: Theme.textTertiary }
            }
            Row {
                id: transport
                anchors { right: parent.right; rightMargin: 10; top: art.top }
                spacing: 2
                Repeater {
                    model: [
                        { g: "\u{f04ae}", on: () => hover.player.previous(), ok: hover.player && hover.player.canGoPrevious },
                        { g: hover.player && hover.player.isPlaying ? "\u{f03e4}" : "\u{f040a}", on: () => hover.player.togglePlaying(), ok: hover.player && hover.player.canTogglePlaying, big: true },
                        { g: "\u{f04ad}", on: () => hover.player.next(), ok: hover.player && hover.player.canGoNext }
                    ]
                    Rectangle {
                        id: tb
                        required property var modelData
                        width: 28; height: 28; radius: 14
                        opacity: modelData.ok ? 1 : 0.35
                        color: tbArea.containsMouse ? Theme.pillHover : "transparent"
                        scale: tbArea.pressed ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                        Text { anchors.centerIn: parent; text: tb.modelData.g; font.family: Theme.fontGlyph; font.pixelSize: tb.modelData.big ? 18 : 15; color: Theme.textPrimary }
                        MouseArea { id: tbArea; anchors.fill: parent; enabled: tb.modelData.ok; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.modelData.on() }
                    }
                }
            }
            // Progress
            Item {
                anchors { left: art.right; leftMargin: 10; right: parent.right; rightMargin: 14; bottom: art.bottom; bottomMargin: 3 }
                height: 4
                readonly property real p: hover.player && hover.player.length > 0 ? Math.min(1, hover.player.position / hover.player.length) : 0
                Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(1, 1, 1, 0.12) }
                Rectangle { width: parent.width * parent.p; height: parent.height; radius: 2; color: Theme.accent }
                Timer { running: hover.visible && hover.player && hover.player.isPlaying; interval: 1000; repeat: true; onTriggered: hover.player.positionChanged() }
            }
        }

        // Nothing playing: how hard the machine is working.
        Row {
            visible: !hover.media
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 18
            StatRing { value: SystemStats.cpu; label: "CPU" }
            StatRing { value: SystemStats.mem; label: "Memory" }
            StatRing {
                value: SystemStats.gpu
                label: "GPU"
                text: SystemStats.gpuState === "suspended" ? "off" : Math.round(SystemStats.gpu * 100) + "%"
            }
            StatRing {
                value: Math.min(1, SystemStats.cpuTemp / 100)
                label: "CPU temp"
                text: SystemStats.cpuTemp ? SystemStats.cpuTemp + "°" : "–"
                color: SystemStats.cpuTemp >= 90 ? Theme.red : SystemStats.cpuTemp >= 80 ? Theme.orange : Theme.green
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Island.open("system", hover.bar.screenName, "pointer") }
        }
    }

    Rectangle { x: 22; y: rowC.y - 10; width: parent.width - 44; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }

    // ── Workspaces, tray, power ──────────────────────────────────────────
    Item {
        id: rowC
        x: 22; y: parent.height - 38
        width: parent.width - 44; height: 24

        Capsules { bar: hover.bar; anchors.verticalCenter: parent.verticalCenter }

        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 14
            TrayRow { window: hover.bar; anchors.verticalCenter: parent.verticalCenter }
            // With media in the middle row, the machine fits in one line here.
            Label {
                visible: hover.media
                anchors.verticalCenter: parent.verticalCenter
                text: "CPU " + Math.round(SystemStats.cpu * 100) + "%  ·  RAM " + Math.round(SystemStats.mem * 100) + "%  ·  GPU " + (SystemStats.gpuState === "suspended" ? "off" : Math.round(SystemStats.gpu * 100) + "%")
                size: 11
                color: Theme.textTertiary
                font.features: ({ "tnum": 1 })
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Island.open("system", hover.bar.screenName, "pointer") }
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                IslandStatus { anchors.verticalCenter: parent.verticalCenter }
                Label {
                    visible: hover.hasBattery
                    anchors.verticalCenter: parent.verticalCenter
                    text: hover.pct + "%"
                    size: 12; weight: Theme.wMedium; rounded: true
                    color: hover.charging ? Theme.green : hover.pct <= 20 ? Theme.red : Theme.textSecondary
                    font.features: ({ "tnum": 1 })
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Notifs.toggleCenter("controls", "pointer") }
            }
        }
    }

    // A small labelled pill (weather, notifications).
    component Chip: Rectangle {
        id: chip
        property string glyph
        property string text
        property string tip
        property color tint: "transparent"
        signal clicked()
        height: 26; radius: 13
        width: chipRow.implicitWidth + 20
        color: chipArea.containsMouse ? Theme.pillHover : tint.a > 0 ? Qt.alpha(tint, 0.18) : Theme.pill
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; text: chip.glyph; font.family: Theme.fontGlyph; font.pixelSize: 13; color: chip.tint.a > 0 ? chip.tint : Theme.textSecondary }
            Label { anchors.verticalCenter: parent.verticalCenter; text: chip.text; size: 12; weight: Theme.wMedium }
        }
        MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }
}
