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
    // On the charger or on battery (UPower's line power), and how long either way.
    readonly property bool onAC: !UPower.onBattery
    function hm(s) { const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60); return h ? h + "h " + m + "m" : m + "m"; }
    readonly property string powerText: !hasBattery ? "" : battery.state === UPowerDeviceState.FullyCharged || (onAC && pct >= 99) ? "Plugged in · full"
        : battery.state === UPowerDeviceState.Charging ? "Charging" + (battery.timeToFull > 0 ? " · full in " + hm(battery.timeToFull) : "")
        : onAC ? "Plugged in · not charging"
        : "On battery" + (battery.timeToEmpty > 0 ? " · " + hm(battery.timeToEmpty) + " left" : "")
    // This week, Monday first (the week strip under the clock).
    readonly property var week: { const d = bar.now, w = []; const mon = new Date(d.getFullYear(), d.getMonth(), d.getDate() - (d.getDay() + 6) % 7); for (let i = 0; i < 7; i++) w.push(new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + i)); return w; }

    implicitWidth: 600
    implicitHeight: 200

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
            Label { width: parent.width; elide: Text.ElideRight; text: hover.app ? hover.app.name : hover.topInfo.class ? hover.topInfo.class.charAt(0).toUpperCase() + hover.topInfo.class.slice(1) : "Desktop"; size: 13; weight: Theme.wSemibold }
            Label { width: parent.width; elide: Text.ElideRight; text: hover.focusWin ? (hover.focusWin.title || "") : "Workspace " + hover.bar.activeWs; size: 11; color: Theme.textTertiary }
        }
        MouseArea {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: right.left }
            cursorShape: Qt.PointingHandCursor
            onClicked: Island.open("launcher", hover.bar.screenName, "pointer", "island")
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
        x: 22; y: 64
        width: parent.width - 44; height: 76

        Item {
          id: when
          anchors.verticalCenter: parent.verticalCenter
          width: whenCol.implicitWidth; height: whenCol.implicitHeight
          Column {
            id: whenCol
            spacing: 10
            IslandClock { now: hover.bar.now; size: 36 }
            // The week, today lit: a glance at the date without the calendar.
            Row {
                spacing: 2
                Repeater {
                    model: hover.week
                    Column {
                        required property var modelData
                        required property int index
                        readonly property bool today: modelData.getDate() === hover.bar.now.getDate()
                        width: 24
                        spacing: 1
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDate(parent.modelData, "ddd").charAt(0); size: 9; weight: Theme.wSemibold; color: parent.today ? Theme.accent : parent.index >= 5 ? Theme.textTertiary : Theme.textSecondary }
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData.getDate(); size: 12; rounded: true; weight: parent.today ? Theme.wSemibold : Theme.wRegular; color: parent.today ? Theme.accent : Theme.textSecondary; font.features: ({ "tnum": 1 }) }
                    }
                }
            }
          }
          HoverHandler { id: whenHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: Island.open("calendar", hover.bar.screenName, "pointer", "island") }
          Tip { text: Qt.formatDate(hover.bar.now, "dddd, d MMMM yyyy") + " · open the calendar"; shown: whenHover.hovered; below: true }
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
            spacing: 16
            StatRing {
                value: SystemStats.cpu; label: "CPU"
                HoverHandler { id: h1 }
                Tip { text: SystemStats.cores.length + " threads · load " + (SystemStats.load.split(" ")[0] || "–"); shown: h1.hovered; below: true }
            }
            StatRing {
                value: SystemStats.mem; label: "Memory"
                HoverHandler { id: h2 }
                Tip { text: SystemStats.bytes(SystemStats.memUsed) + " of " + SystemStats.bytes(SystemStats.memTotal) + (SystemStats.swapUsed > 1073741824 ? " · swap " + SystemStats.bytes(SystemStats.swapUsed) : ""); shown: h2.hovered; below: true }
            }
            StatRing {
                value: SystemStats.gpu
                label: "GPU"
                text: SystemStats.gpuState === "suspended" ? "off" : Math.round(SystemStats.gpu * 100) + "%"
                HoverHandler { id: h3 }
                Tip { text: SystemStats.gpuState === "suspended" ? "NVIDIA asleep · Intel drives the screens" : "NVIDIA " + SystemStats.gpuTemp + "° · " + Math.round(SystemStats.gpuPower) + " W · Intel " + SystemStats.igpuMHz + " MHz"; shown: h3.hovered; below: true }
            }
            StatRing {
                value: Math.min(1, SystemStats.cpuTemp / 100)
                label: "Temp"
                text: SystemStats.cpuTemp ? SystemStats.cpuTemp + "°" : "–"
                color: SystemStats.cpuTemp >= 90 ? Theme.red : SystemStats.cpuTemp >= 80 ? Theme.orange : Theme.green
                HoverHandler { id: h4 }
                Tip { text: "CPU " + SystemStats.cpuTemp + "° · GPU " + SystemStats.gpuTemp + "°" + (SystemStats.fans.length ? " · fans " + SystemStats.fans.join(" / ") + " rpm" : ""); shown: h4.hovered; below: true }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Island.open("system", hover.bar.screenName, "pointer", "island") }
        }
    }

    Rectangle { x: 22; y: rowC.y - 14; width: parent.width - 44; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

    // ── Workspaces, tray, power ──────────────────────────────────────────
    Item {
        id: rowC
        x: 22; y: parent.height - 36
        width: parent.width - 44; height: 24

        Capsules { bar: hover.bar; anchors.verticalCenter: parent.verticalCenter }
        Item {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: batRow.width
            Tip { text: hover.powerText; shown: batHover.hovered }
        }

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
                TapHandler { onTapped: Island.open("system", hover.bar.screenName, "pointer", "island") }
            }
            Row {
                id: batRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                IslandStatus { anchors.verticalCenter: parent.verticalCenter }
                // On the charger: a plug; on battery: nothing extra.
                Text {
                    visible: hover.hasBattery && hover.onAC
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f06a5}"
                    font.family: Theme.fontGlyph; font.pixelSize: 13
                    color: hover.charging ? Theme.green : Theme.textSecondary
                }
                Label {
                    visible: hover.hasBattery
                    anchors.verticalCenter: parent.verticalCenter
                    text: hover.pct + "%"
                    size: 12; weight: Theme.wMedium; rounded: true
                    color: hover.charging ? Theme.green : hover.pct <= 20 ? Theme.red : Theme.textSecondary
                    font.features: ({ "tnum": 1 })
                }
                HoverHandler { id: batHover; cursorShape: Qt.PointingHandCursor }
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
