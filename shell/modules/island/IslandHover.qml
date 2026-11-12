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
    readonly property bool agentsHere: Settings.limitAlerts && Limits.usable.length > 0
    required property var bar
    readonly property Item clockItem: hoverClock
    property bool clockHidden: false
    readonly property var player: bar.player
    readonly property bool media: bar.showMedia
    // Go to the window that's playing: the one whose title carries the track
    // (a browser tab: "ADDICTED - YouTube"), else the player app's window,
    // else ask the player to raise itself (MPRIS Raise).
    function goToPlayer(p) { Media.goTo(p); }
    // This screen's window (bar.screenWin), not the one focused on another screen.
    readonly property var focusWin: bar.screenWin
    readonly property var topInfo: focusWin && focusWin.lastIpcObject ? focusWin.lastIpcObject : ({})
    // Hyprland's class; else the Wayland app id (a window the shell hasn't asked Hyprland about yet).
    readonly property string winClass: topInfo.class || (focusWin && focusWin.wayland ? (focusWin.wayland.appId || "") : "")
    readonly property var app: winClass ? DesktopEntries.heuristicLookup(winClass) : null

    // Wide enough that the centre row (the machine's rings and your agents'),
    // centred, never runs under the workspaces on the left or the status rows
    // on the right: 720 normally, wider with many accounts, never past the
    // window (IslandBar takes this as the grown shape's width). Past that the
    // agents strip shows what fits and a "+N" (agents.room).
    readonly property real gap: 16
    readonly property real sideW: Math.max(28 + caps.width, 28 + rightCol.width)
    readonly property real maxW: Math.max(720, bar.implicitWidth - 40)
    // With music the card is the centre: the right column (the updates chip,
    // the status icons) ran under it at a fixed 720.
    readonly property real needW: Math.ceil(2 * (sideW + gap) + (hover.media ? card.width : centreRow.width))
    // While open it may grow (an account arrives) but never shrinks back: a
    // chip or the quick shelf changing size under the pointer would otherwise
    // resize the island and slide everything centred in it. Each opening
    // starts over (the view is loaded fresh).
    property real heldW: 720
    onNeedWChanged: if (needW > heldW) heldW = needW
    implicitWidth: Math.min(maxW, Math.max(720, heldW))
    // Music playing: a second row under Now Playing for the machine and your
    // agents (they used to vanish, then to widen the island beside the card).
    readonly property real mediaRowH: hover.media ? 42 : 0
    implicitHeight: 148 + mediaRowH + (OllamaService.recentWork.length || OllamaService.bgWorking ? 38 : 0)

    // Recent background work from the assistant (done or failed while its panel
    // was closed): click one to open that chat.
    Row {
        visible: OllamaService.recentWork.length > 0 || OllamaService.bgWorking
        x: 18
        y: 148 + hover.mediaRowH
        height: 30
        spacing: 8
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: "Assistant"
            size: 11
            weight: Theme.wSemibold
            color: Theme.textTertiary
        }
        // What it's doing right now, in the shimmer the panel uses for thinking.
        Rectangle {
            visible: OllamaService.bgWorking
            height: 26
            width: nowRow.implicitWidth + 18
            radius: 13
            color: Qt.rgba(1, 1, 1, nowArea.containsMouse ? 0.12 : 0.07)
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            Row {
                id: nowRow
                anchors.centerIn: parent
                spacing: 6
                Shimmer {
                    anchors.verticalCenter: parent.verticalCenter
                    text: OllamaService.pendingRequest ? "Needs you" : (OllamaService.bgLabel || "Thinking")
                    size: 12
                    color: OllamaService.pendingRequest ? Theme.orange : Theme.textSecondary
                    active: !OllamaService.pendingRequest
                }
                Label {
                    visible: OllamaService.bgSecs >= 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: OllamaService.bgSecs + "s"
                    size: 12
                    color: Theme.textTertiary
                    font.features: ({ "tnum": 1 })
                }
            }
            MouseArea { id: nowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: OllamaService.openSession(OllamaService.draftSessionId) }
        }
        Repeater {
            model: OllamaService.recentWork.slice(0, OllamaService.bgWorking ? 1 : 2)   // two fit on the row
            Rectangle {
                id: workChip
                required property var modelData
                height: 26
                width: workRow.implicitWidth + 16
                radius: 13
                color: Qt.rgba(1, 1, 1, workArea.containsMouse ? 0.12 : 0.07)
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                Row {
                    id: workRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: workChip.modelData.status === "done" ? "check-circle" : "warning-circle"
                        style: "fill"
                        size: 12
                        color: workChip.modelData.status === "done" ? Theme.green : Theme.red
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: workChip.modelData.title
                        size: 12
                        color: Theme.textSecondary
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 200)
                    }
                }
                MouseArea { id: workArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: OllamaService.openSession(workChip.modelData.sessionId) }
            }
        }
    }

    Component.onCompleted: { SystemStats.watch(); heldW = Math.max(720, needW); }
    Component.onDestruction: SystemStats.unwatch()

    // ── Left: where ──────────────────────────────────────────────────────
    Column {
        x: 28; y: 24
        width: 200
        spacing: 16
        Row {
            spacing: 8
            // Quieter on a screen that isn't focused, like its pills.
            opacity: hover.bar.focusedHere ? 1 : 0.55
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
                text: hover.app ? hover.app.name : hover.winClass ? hover.winClass.charAt(0).toUpperCase() + hover.winClass.slice(1) : "Desktop"
                size: 14; weight: Theme.wMedium
            }
            HoverHandler { id: appHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Island.open("launcher", hover.bar.screenName, "pointer", "island") }
        }
        Capsules { id: caps; bar: hover.bar; scale: 1.1 }
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
                id: hoverClock
                opacity: hover.clockHidden ? 0 : 1   // not visible: the Row would close up under the flying clock
                now: hover.bar.now; size: Theme.tClock
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
            // Weather beside the date (services/Weather): glyph and degrees,
            // conditions in the tooltip. Not on the resting island.
            Label {
                visible: Settings.restWeather && Weather.ok
                anchors.verticalCenter: parent.verticalCenter
                text: "·"; size: 15; color: Theme.textTertiary
            }
            Row {
                visible: Settings.restWeather && Weather.ok
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.glyph; font.family: Theme.fontGlyph; font.pixelSize: 17
                    color: Theme.textSecondary
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.temp + "°"
                    size: 15; weight: Theme.wMedium; rounded: true
                    color: Theme.textSecondary
                }
                HoverHandler { id: wxHover }
                Tip { text: Weather.desc + " · feels " + Weather.feels + "° · " + Weather.humidity + "% humidity · " + Weather.wind + " km/h"; shown: wxHover.hovered; below: true }
            }
        }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { hover.bar.clockFrom(hoverClock); Island.open("calendar", hover.bar.screenName, "pointer", "island"); } }
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
            ImageEdge { radius: 11 }
        }
        // The art and the title open Now Playing (MediaPanel); right-click for
        // the sound panel (outputs, per-app volume).
        MouseArea {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: trail.left }
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                // Click: Now Playing (scrub, shuffle, repeat, output). Right-click: the Sound tab.
                if (mouse.button === Qt.RightButton) Notifs.toggleCenter("sound", "pointer", hover.bar.screenName);
                else Island.open("media", hover.bar.screenName, "pointer", "island");
            }
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
            readonly property real level: peak.enabled ? (peak.peaks && peak.peaks.length ? Math.max(...peak.peaks) : (peak.peak || 0)) : 0
            Row {
                anchors.centerIn: parent
                spacing: 4
                opacity: cardHover.hovered ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.microMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                Repeater {
                    model: 13
                    Rectangle {
                        required property int index
                        readonly property real shape: 0.35 + 0.65 * Math.sin(Math.PI * (index + 0.5) / 13)
                        property real jitter: 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; radius: 1.5
                        readonly property bool live: hover.player && hover.player.isPlaying
                        readonly property real liveH: Math.max(3, 24 * Math.min(1, trail.level * shape * jitter * 1.7))
                        readonly property real pauseH: Math.max(4, 22 * shape * 0.42)
                        height: live ? liveH : pauseH
                        color: Media.artColor
                        opacity: live ? 0.9 : 0.5
                        Behavior on height { NumberAnimation { duration: live ? 90 : 380; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
                        Timer { running: peak.enabled && !Theme.reduceMotion; interval: 110 + (index % 4) * 35; repeat: true; onTriggered: parent.jitter = 0.65 + Math.random() * 0.55 }
                    }
                }
            }
            Row {
                anchors.centerIn: parent
                spacing: 4
                opacity: cardHover.hovered ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Theme.microMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
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
                width: parent.width * Media.fraction
                height: parent.height; radius: 1
                color: Qt.alpha(Media.artColor, 0.85)
            }
            Component.onCompleted: Media.watch()
            Component.onDestruction: Media.unwatch()
        }
    }

    // ── Music playing: the machine and your agents, a row under the card ──
    // Small rings without names (the line under them names the one under the
    // pointer): CPU, Memory, GPU, Temp, then each account you can use (outer:
    // session, inner: weekly, its logo inside). Click: System, or that agent
    // in Usage. The island keeps its width; the row fits under the card.
    property string hotText: ""
    Row {
        id: mediaRow
        visible: hover.media
        anchors.horizontalCenter: parent.horizontalCenter
        y: card.y + card.height + 10
        height: 28
        spacing: 8
        readonly property int ring: 28
        // Room across the island (the side columns end above this row).
        readonly property int room: Math.max(1, Math.floor((hover.width - 56 - 4 * (ring + 8) - 17 + 8) / (ring + 8)))
        readonly property var shown: Limits.usable.length <= room ? Limits.usable : Limits.usable.slice(0, room - 1)
        readonly property int more: Limits.usable.length - shown.length
        Repeater {
            model: [
                { k: "CPU", g: "\u{f061a}", v: () => SystemStats.cpu, line: () => "CPU " + Math.round(SystemStats.cpu * 100) + "% · " + SystemStats.cores.length + " threads" },
                { k: "Memory", g: "\u{f035b}", v: () => SystemStats.mem, line: () => "Memory " + Math.round(SystemStats.mem * 100) + "% · " + SystemStats.bytes(SystemStats.memUsed) + " of " + SystemStats.bytes(SystemStats.memTotal) },
                { k: "GPU", g: "\u{f08ae}", v: () => SystemStats.gpuState === "suspended" ? 0 : SystemStats.gpu, line: () => SystemStats.gpuState === "suspended" ? "NVIDIA asleep · Intel drives the screens" : "GPU " + Math.round(SystemStats.gpu * 100) + "% · " + SystemStats.gpuTemp + "°" },
                { k: "Temp", g: "\u{f050f}", v: () => Math.min(1, SystemStats.cpuTemp / 100), line: () => "CPU " + SystemStats.cpuTemp + "° · GPU " + SystemStats.gpuTemp + "°", temp: true }
            ]
            delegate: StatRing {
                required property var modelData
                size: mediaRow.ring; stroke: 2.5
                value: modelData.v()
                text: ""; label: ""
                color: !modelData.temp ? Theme.accent : SystemStats.cpuTemp >= 90 ? Theme.red : SystemStats.cpuTemp >= 80 ? Theme.orange : Theme.green
                // What it measures, inside the ring (chip, memory, card, thermometer):
                // four bare rings beside the agents' logos read as four more agents.
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData.g
                    font.family: Theme.fontGlyph
                    font.pixelSize: 12
                    color: Theme.textSecondary
                }
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: hover.hotText = hovered ? parent.modelData.line() : (hover.hotText === parent.modelData.line() ? "" : hover.hotText)
                }
                TapHandler { onTapped: Island.open("system", hover.bar.screenName, "pointer", "island") }
            }
        }
        Rectangle {
            visible: hover.agentsHere
            anchors.verticalCenter: parent.verticalCenter
            width: 1; height: 20
            color: Theme.cardEdge
        }
        Repeater {
            model: ScriptModel { values: hover.agentsHere ? mediaRow.shown : []; objectProp: "id" }
            delegate: Item {
                id: mag
                required property var modelData
                readonly property var e: modelData
                width: mediaRow.ring; height: mediaRow.ring
                function ink(w) { return !w ? Theme.track : w.out ? Theme.red : w.near ? Theme.orange : mag.e.tint; }
                StatRing {
                    size: mediaRow.ring; stroke: 2.5
                    value: mag.e.session ? Math.max(0, mag.e.session.left) : 0
                    color: mag.ink(mag.e.session)
                    text: ""; label: ""
                }
                StatRing {
                    visible: !!mag.e.weekly
                    x: 5; y: 5
                    size: mediaRow.ring - 10; stroke: 2
                    value: mag.e.weekly ? Math.max(0, mag.e.weekly.left) : 0
                    color: mag.ink(mag.e.weekly)
                    text: ""; label: ""
                    opacity: 0.85
                }
                Image {
                    anchors.centerIn: parent
                    width: 10; height: 10
                    source: mag.e.brand
                    sourceSize: Qt.size(20, 20)
                    asynchronous: true
                }
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: agents.hot = hovered ? mag.e : (agents.hot === mag.e ? null : agents.hot)
                }
                TapHandler { onTapped: { Limits.usageTab = mag.e.pid; Island.open("usage", hover.bar.screenName, "pointer", "island"); } }
            }
        }
        Item {
            visible: hover.agentsHere && mediaRow.more > 0
            width: mediaRow.ring; height: mediaRow.ring
            Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: 2.5; border.color: Theme.track }
            Label { anchors.centerIn: parent; text: "+" + mediaRow.more; size: 10; weight: Theme.wSemibold; color: Theme.textSecondary }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Island.open("usage", hover.bar.screenName, "pointer", "island") }
        }
    }

    // Nothing playing: how hard the machine works.
    Row {
        id: centreRow
        visible: !hover.media
        anchors.horizontalCenter: parent.horizontalCenter
        // With agents beside the machine: tighter. No offset: the island's
        // width (needW) keeps both sides clear.
        y: 64
        spacing: hover.agentsHere ? 14 : 22
        // The machine. With your agents beside it there's room for two rings:
        // CPU and Memory, and resting on them a moment turns the page to GPU
        // and Temp (a crossfade with a small lift; leaving turns it back).
        // Without agents all four sit in one row.
        Item {
            id: machine
            readonly property bool paged: hover.agentsHere
            property int page: 0
            width: paged ? Math.max(pageA.width, pageB.width) : pageA.width + 22 + pageB.width
            height: pageA.height
            HoverHandler { id: machineHover }
            Timer { interval: 700; running: machine.paged && machineHover.hovered && machine.page === 0; onTriggered: machine.page = 1 }
            Timer { interval: Theme.hoverLeaveMs; running: machine.page === 1 && !machineHover.hovered; onTriggered: machine.page = 0 }
            Row {
                id: pageA
                spacing: hover.agentsHere ? 14 : 22
                opacity: !machine.paged || machine.page === 0 ? 1 : 0
                y: !machine.paged || machine.page === 0 || Theme.reduceMotion ? 0 : -4
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                Behavior on y { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
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
            }
            Row {
                id: pageB
                x: machine.paged ? 0 : pageA.width + 22
                spacing: hover.agentsHere ? 14 : 22
                opacity: !machine.paged || machine.page === 1 ? 1 : 0
                y: !machine.paged || machine.page === 1 || Theme.reduceMotion ? 0 : 4
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                Behavior on y { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
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
            }
            // Its own click (System); the agents' rings have theirs (Usage), so a
            // click on Claude no longer falls through to System.
            TapHandler { onTapped: Island.open("system", hover.bar.screenName, "pointer", "island") }
        }
        // Your agents beside the machine: what each has LEFT (its worst
        // window), in its own colour, its logo inside; red when out. Claude
        // first, then the tightest. The notch at rest stays quiet about usage;
        // this is where you look (click: the Usage panel).
        Rectangle {
            visible: hover.agentsHere
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -8
            width: 1; height: 28
            color: Theme.cardEdge
        }
        // Every account you can use now (outer ring: the session window,
        // inner: the weekly one); spent ones are left out (Limits.usable), the
        // Usage panel lists every one. Click: that agent's tab in Usage.
        Item {
            id: agents
            visible: hover.agentsHere
            readonly property var all: Limits.usable
            // Each column the same width (a ring and its name under it): the name
            // used to widen its ring's StatRing, centring the outer ring on
            // "Antigravity 1" while the inner ring and logo stayed put.
            readonly property int col: Theme.statRingSize + 26
            // Columns that fit at the island's widest (14 + divider + 14 before
            // the strip). More accounts than that: the last column is "+N".
            readonly property int room: Math.max(1, Math.floor((hover.maxW - 2 * (hover.sideW + hover.gap) - machine.width - 29 + 6) / (col + 6)))
            readonly property var shown: all.length <= room ? all : all.slice(0, room - 1)
            readonly property int more: all.length - shown.length
            readonly property int cols: shown.length + (more > 0 ? 1 : 0)
            width: Math.max(col, cols * col + Math.max(0, cols - 1) * 6)
            height: Theme.statRingSize + 18
            // The account under the pointer. Its windows stay in the island:
            // a popup below the ring drew on the window underneath, with no pill.
            property var hot: null
            function line(w) {
                if (!w) return "";
                return w.label + ": " + (w.out ? "out · back in " : Math.round(w.left * 100) + "% left · resets in ") + Limits.resetsIn(w.window);
            }
            Row {
                id: agentsRow
                spacing: 6
                Repeater {
                    model: ScriptModel { values: agents.shown; objectProp: "id" }
                    delegate: Item {
                        id: ag
                        required property var modelData
                        readonly property var e: modelData
                        width: agents.col
                        height: Theme.statRingSize + 18
                        readonly property real rx: (width - Theme.statRingSize) / 2
                        function ink(w) { return !w ? Theme.track : w.out ? Theme.red : w.near ? Theme.orange : ag.e.tint; }
                        // Outer: the session window.
                        StatRing {
                            x: ag.rx
                            size: Theme.statRingSize; stroke: 3
                            value: ag.e.session ? Math.max(0, ag.e.session.left) : 0
                            color: ag.ink(ag.e.session)
                            text: ""; label: ""
                        }
                        // Inner: the weekly window.
                        StatRing {
                            visible: !!ag.e.weekly
                            x: ag.rx + 6; y: 6
                            size: Theme.statRingSize - 12; stroke: 2.5
                            value: ag.e.weekly ? Math.max(0, ag.e.weekly.left) : 0
                            color: ag.ink(ag.e.weekly)
                            text: ""; label: ""
                            opacity: 0.85
                        }
                        // The name, under its ring, the same type as CPU/Memory's.
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Theme.statRingSize + 4         // StatRing's own spacing: on CPU/Memory's baseline
                            width: Math.min(implicitWidth, ag.width)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: ag.e.label
                            size: 11; weight: Theme.wMedium; color: Theme.textSecondary
                        }
                        Image {
                            x: ag.rx + (Theme.statRingSize - width) / 2; y: (Theme.statRingSize - height) / 2
                            width: 12; height: 12
                            source: ag.e.brand
                            sourceSize: Qt.size(24, 24)
                            asynchronous: true
                        }
                        HoverHandler {
                            onHoveredChanged: agents.hot = hovered ? ag.e : (agents.hot === ag.e ? null : agents.hot)
                        }
                        TapHandler { onTapped: { Limits.usageTab = ag.e.pid; Island.open("usage", hover.bar.screenName, "pointer", "island"); } }
                    }
                }
                // The accounts that didn't fit: a count in a quiet ring; the
                // Usage panel lists every one.
                Item {
                    visible: agents.more > 0
                    width: agents.col
                    height: Theme.statRingSize + 18
                    Rectangle {
                        x: (parent.width - Theme.statRingSize) / 2
                        width: Theme.statRingSize; height: Theme.statRingSize; radius: width / 2
                        color: "transparent"
                        border.width: 3; border.color: Theme.track
                        Label { anchors.centerIn: parent; text: "+" + agents.more; size: 12; weight: Theme.wSemibold; color: Theme.textSecondary }
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Theme.statRingSize + 4
                        text: "More"
                        size: 11; weight: Theme.wMedium; color: Theme.textSecondary
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Island.open("usage", hover.bar.screenName, "pointer", "island") }
                }
            }
        }
    }
    // The account under the pointer. Inside the island: a popup under the
    // ring sat on the window below, and the line had no pill.
    Label {
        visible: text !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        y: hover.media ? mediaRow.y + mediaRow.height + 3 : 126
        width: Math.min(implicitWidth, 460)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: {
            const e = agents.hot;
            if (!e) return hover.media ? hover.hotText : "";
            return e.label + " · " + [agents.line(e.session), agents.line(e.weekly)].filter(x => x).join(" · ");
        }
        size: 11
        weight: Theme.wMedium
        color: Theme.textSecondary
    }

    // ── Right: news and status ───────────────────────────────────────────
    Column {
        id: rightCol
        anchors { right: parent.right; rightMargin: 28 }
        y: 22
        spacing: 16
        // Top right: the quick switches, then the bell.
        Row {
            anchors.right: parent.right
            spacing: 16
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                // Quick switches: one shown (pinned; Caffeine first), the rest a
            // hold away in a shelf (QuickShelf). Adding one is one entry here.
            PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }
            QuickShelf {
                anchors.verticalCenter: parent.verticalCenter
                readonly property var src: Pipewire.defaultAudioSource
                readonly property var sink: Pipewire.defaultAudioSink
                readonly property bool micMuted: !!src && !!src.audio && src.audio.muted
                readonly property bool spkMuted: !!sink && !!sink.audio && sink.audio.muted
                readonly property int vol: sink && sink.audio ? Math.round(sink.audio.volume * 100) : 0
                items: [
                    { id: "caffeine", glyph: "\u{f0176}", on: Caffeine.on, tone: Theme.yellow, alert: Caffeine.on,
                      tip: Caffeine.on ? "Caffeine on: no dim, lock or sleep" : "Caffeine: keep awake", toggle: () => Caffeine.toggle() },
                    { id: "mic", glyph: "\u{f036c}", glyphOff: "\u{f036d}", on: !micMuted, alert: micMuted,
                      tone: Activities.micInUse ? Theme.orange : Theme.textPrimary, offTone: Theme.red,
                      tip: (micMuted ? "Microphone muted" : "Microphone on")
                          + (Activities.micName ? " · " + Activities.micName : "")
                          + (Activities.voxListening ? "" : (!micMuted && Activities.micInUse && Activities.micUseSummary ? " · in use by " + Activities.micUseSummary : "")),
                      toggle: () => { if (src && src.audio) src.audio.muted = !src.audio.muted; } },
                    { id: "speaker", glyph: vol >= 60 ? "\u{f057e}" : vol >= 25 ? "\u{f0580}" : "\u{f057f}", glyphOff: "\u{f075f}", on: !spkMuted, alert: spkMuted,
                      tone: Theme.textPrimary, offTone: Theme.red,
                      tip: (spkMuted ? "Muted" : "Volume " + vol + "%") + " · scroll to change",
                      toggle: () => { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted; },
                      wheel: steps => { if (sink && sink.audio) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1.5, Math.round((sink.audio.volume + steps * 0.05) * 20) / 20)); } } },
                    { id: "focus", glyph: "\u{f0594}", on: Notifs.dnd, alert: Notifs.dnd, tone: Theme.focus,
                      tip: Notifs.dnd ? "Focus on: notifications held" : "Focus (Do Not Disturb)", toggle: () => { Notifs.toggleUserDnd(); } },
                    { id: "night", glyph: "\u{f0599}", on: Display.nightOn, alert: false, tone: Theme.orange,
                      tip: Display.nightHeld ? "Night Shift paused while Accurate" : Display.nightOn ? "Night Shift on" : "Night Shift", toggle: () => Display.toggleNight() },
                    // Display preset: scroll through them here; click opens Controls.
                    { id: "display", glyph: "\u{f0379}", on: Display.preset !== "everyday", alert: false, tone: Theme.cyan,
                      tip: "Display: " + Display.presetInfo(Display.preset).label
                          + (Display.auto !== "" && Display.choice === "everyday" ? " (automatic)" : "") + " · scroll to change",
                      toggle: () => Notifs.toggleCenter("controls", "pointer", hover.bar.screenName),
                      wheel: steps => Display.cyclePreset(steps > 0 ? 1 : -1) },
                    // The AI assistant: lit while it works, a dot when it needs you; click opens it.
                    { id: "assistant", glyph: "\u{f0674}", on: OllamaService.streaming, alert: !!OllamaService.pendingRequest, tone: Theme.accent,
                      tip: OllamaService.pendingRequest ? "Assistant: needs you" : OllamaService.streaming ? "Assistant: " + (OllamaService.bgLabel || "working") : "Assistant · Super+Ctrl+Shift+A",
                      toggle: () => Assistant.show() }
                ]
            }
            }
        // Vitals: the GPU, the machine and the agents' usage in one panel. A dot
        // when an agent is out of its limit.
        QuickIcon {
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\u{f029a}"
            on: Island.panel === "vitals"
            tone: Theme.accent
            badge: Limits.exhausted.length > 0
            badgeTone: Theme.orange
            tip: "Vitals: GPU, machine and agent usage"
                + (Limits.exhausted.length ? " · " + Limits.exhausted.length + " agent" + (Limits.exhausted.length === 1 ? "" : "s") + " out" : "")
            onClicked: Island.open("vitals", hover.bar.screenName, "pointer", "island")
        }
        Item {
            id: bellRow
            anchors.verticalCenter: parent.verticalCenter
            width: bell.implicitWidth
            height: bell.implicitHeight
            BellIcon {
                id: bell
                count: Notifs.inbox
                muted: Notifs.muted
                dnd: Notifs.dnd
                missed: Notifs.missed.length > 0
                urgent: Notifs.missed.some(i => i.severity === "critical")
                badgeTone: Notifs.bellBadgeTone
                tip: Notifs.bellTip
                onTapped: Notifs.toggleCenter("notifications", "pointer", hover.bar.screenName)
                // Right-click / hold: the island grows into the list (NotifsPanel).
                onQuickPressed: Island.open("notifs", hover.bar.screenName, "pointer", "island")
            }
            HoverHandler { id: bellHover; cursorShape: Qt.PointingHandCursor }
        }
        }
        Row {
            anchors.right: parent.right
            spacing: 14
            // Updates, only when there are some (or one is running): a quiet
            // accent chip with the count, the run's ring and % while it
            // installs. Click: Software Update.
            Rectangle {
                id: updChip
                visible: Updates.running || Updates.total > 0
                anchors.verticalCenter: parent.verticalCenter
                height: 24; radius: 12
                width: updRow.implicitWidth + 16
                Behavior on width { NumberAnimation { duration: Theme.reflowMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                clip: true
                scale: updArea.pressed ? 0.96 : 1
                Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.OutCubic } }
                readonly property bool hot: updArea.containsMouse
                color: Qt.alpha(Theme.accent, Updates.running ? 0.12 : hot ? 0.28 : 0.16)
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                // Installing: the pill is the progress bar, a fill sweeping
                // across behind the words.
                Rectangle {
                    visible: Updates.running
                    height: parent.height
                    radius: parent.radius
                    width: Math.max(parent.height, parent.width * Math.max(0.04, Math.min(1, Updates.progress)))
                    color: Qt.alpha(Theme.accent, 0.30)
                    Behavior on width { NumberAnimation { duration: Theme.artMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                }
                Row {
                    id: updRow
                    anchors.centerIn: parent
                    spacing: 5
                    Icon {
                        visible: !Updates.running
                        anchors.verticalCenter: parent.verticalCenter
                        name: "arrow-circle-up"; size: 14
                        color: Theme.accent
                        active: updChip.hot
                    }
                    Label {
                        visible: Updates.running
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Installing"
                        size: Theme.tSub; weight: Theme.wMedium
                        color: Theme.accent
                    }
                    RollingNumber {
                        anchors.verticalCenter: parent.verticalCenter
                        value: Updates.running ? Math.round(Updates.progress * 100) : Updates.total
                        suffix: Updates.running ? "%" : ""
                        size: Theme.tSub; weight: Theme.wSemibold
                        color: Theme.accent
                    }
                    // "4 updates", always: hover only tints it and the tip says
                    // what a click does. Revealing "· Install" widened the
                    // chip, which resized the island and slid everything in it.
                    // With music the chip is just the arrow and the count: the
                    // word made the right column run under the card.
                    Label {
                        visible: !Updates.running && !hover.media
                        anchors.verticalCenter: parent.verticalCenter
                        text: Updates.total === 1 ? "update" : "updates"
                        size: Theme.tSub; weight: Theme.wMedium
                        color: Theme.accent
                    }
                }
                MouseArea {
                    id: updArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) { updMenu.confirmAll = false; updMenu.open = !updMenu.open; }
                        else Island.open("updates", hover.bar.screenName, "pointer", "island");
                    }
                }
                // Right-click: the quick routes (same menu as the tray's).
                TrayMenu {
                    id: updMenu
                    property bool confirmAll: false
                    anchorItem: updChip
                    anchorHovered: updArea.containsMouse
                    window: hover.bar
                    property bool counted: false
                    onOpenChanged: {
                        if (open && !counted) { counted = true; hover.bar.menus++; }
                        else if (!open && counted) { counted = false; hover.bar.menus = Math.max(0, hover.bar.menus - 1); }
                    }
                    items: Updates.running ? [
                        { text: "Show progress", glyph: "\u{f06b0}", triggered: () => Island.open("updates", hover.bar.screenName, "pointer", "island") }
                    ] : [
                        { text: "Review and update", glyph: "\u{f06b0}", triggered: () => Island.open("updates", hover.bar.screenName, "pointer", "island") },
                        { text: updMenu.confirmAll ? "Click again: AUR without review" : "Update everything now", glyph: "\u{f0e4f}", danger: updMenu.confirmAll, keepOpen: !updMenu.confirmAll,
                          enabled: Updates.total > 0, triggered: () => { if (!updMenu.confirmAll) { updMenu.confirmAll = true; return; } Updates.runAll(); } },
                        { text: "Update in a terminal (sysup)", glyph: "\u{f018d}", triggered: () => Updates.terminal() },
                        { isSeparator: true },
                        { text: "Check again", glyph: "\u{f0450}", triggered: () => Updates.check() }
                    ]
                }
                Tip {
                    text: Updates.running ? "Updating · " + Updates.phaseLabel
                        : Updates.repo.length + " Arch · " + Updates.aur.length + " AUR" + (Updates.waitingReview ? " · " + Updates.waitingReview + " to review" : "") + " · click to install"
                    shown: updArea.containsMouse
                    below: true
                }
            }
            TrayRow { window: hover.bar; anchors.verticalCenter: parent.verticalCenter }
            IslandStatus { anchors.verticalCenter: parent.verticalCenter; bar: hover.bar; showBluetooth: true }
        }
    }
}
