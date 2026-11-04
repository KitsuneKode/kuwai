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

    implicitWidth: 780   // room for the quick switches beside the bell
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
                        color: Media.artColor
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
                width: parent.width * Media.fraction
                height: parent.height; radius: 1
                color: Qt.alpha(Media.artColor, 0.85)
            }
            Component.onCompleted: Media.watch()
            Component.onDestruction: Media.unwatch()
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
                      tip: (micMuted ? "Microphone muted" : "Microphone on") + (Activities.micName ? " · " + Activities.micName : "") + (!micMuted && Activities.micInUse ? " · in use by " + [...new Set(Activities.micUsers)].join(", ") : ""),
                      toggle: () => { if (src && src.audio) src.audio.muted = !src.audio.muted; } },
                    { id: "speaker", glyph: vol >= 60 ? "\u{f057e}" : vol >= 25 ? "\u{f0580}" : "\u{f057f}", glyphOff: "\u{f075f}", on: !spkMuted, alert: spkMuted,
                      tone: Theme.textPrimary, offTone: Theme.red,
                      tip: (spkMuted ? "Muted" : "Volume " + vol + "%") + " · scroll to change",
                      toggle: () => { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted; },
                      wheel: steps => { if (sink && sink.audio) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1.5, Math.round((sink.audio.volume + steps * 0.05) * 20) / 20)); } } },
                    { id: "focus", glyph: "\u{f0594}", on: Notifs.dnd, alert: Notifs.dnd, tone: "#bf5af2",
                      tip: Notifs.dnd ? "Focus on: notifications held" : "Focus (Do Not Disturb)", toggle: () => { Notifs.dnd = !Notifs.dnd; } },
                    { id: "night", glyph: "\u{f0599}", on: Display.nightOn, alert: false, tone: Theme.orange,
                      tip: Display.nightOn ? "Night Shift on" : "Night Shift", toggle: () => Display.toggleNight() }
                ]
            }
            }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            id: bellRow
            Label { anchors.verticalCenter: parent.verticalCenter; text: Notifs.missed.length ? Notifs.missed.length + " to look at" : Notifs.unread ? Notifs.unread + " new" : "All caught up"; size: 14; weight: Theme.wMedium; color: Theme.textPrimary }   // white: the accent means "where you are"
            Icon { anchors.verticalCenter: parent.verticalCenter; name: Notifs.dnd ? "bell-slash" : "bell"; size: 16; active: Notifs.unread > 0; color: Notifs.unread ? Theme.accent : Theme.textSecondary }
            // Rest on it: the missed ones, each with its buttons. Click: the center.
            HoverHandler { id: bellHover; cursorShape: Qt.PointingHandCursor }
            Timer { running: bellHover.hovered && Notifs.missed.length > 0 && !missedMenu.open; interval: Settings.hoverDelay; onTriggered: missedMenu.open = true }
            TapHandler { onTapped: { missedMenu.open = false; Notifs.toggleCenter("notifications", "pointer", hover.bar.screenName); } }
            TrayMenu {
                id: missedMenu
                anchorItem: bellRow
                anchorHovered: bellHover.hovered
                window: hover.bar
                property bool counted: false
                onOpenChanged: {
                    if (open && !counted) { counted = true; hover.bar.menus++; }
                    else if (!open && counted) { counted = false; hover.bar.menus = Math.max(0, hover.bar.menus - 1); }
                }
                items: {
                    const out = [];
                    for (const it of Notifs.missed.slice(0, 5)) {
                        if (out.length) out.push({ isSeparator: true });
                        const tone = it.severity === "critical" ? "\u{f0026}" : it.severity === "warning" ? "\u{f0028}" : "\u{f009a}";
                        out.push({ text: (it.title || it.app) + (it.app && it.title ? "  ·  " + it.app : ""), glyph: tone, triggered: () => Notifs.activate(it) });
                        for (const a of (it.actions || []).slice(0, 3))
                            out.push({ text: "    " + a.text, glyph: "\u{f0142}", triggered: () => Notifs.invokeAction(it, a.id) });
                    }
                    if (Notifs.missed.length > 5) out.push({ isSeparator: true }, { text: (Notifs.missed.length - 5) + " more in the center…", glyph: "\u{f009a}", triggered: () => Notifs.toggleCenter("notifications", "pointer", hover.bar.screenName) });
                    return out;
                }
            }
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
                color: updArea.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                Row {
                    id: updRow
                    anchors.centerIn: parent
                    spacing: 5
                    StatRing {
                        visible: Updates.running
                        anchors.verticalCenter: parent.verticalCenter
                        size: 14; stroke: 2; text: ""; label: ""
                        value: Updates.progress; color: Theme.accent
                    }
                    Icon {
                        visible: !Updates.running
                        anchors.verticalCenter: parent.verticalCenter
                        name: "arrow-circle-up"; size: 14
                        color: Theme.accent
                        active: updArea.containsMouse
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Updates.running ? Math.round(Updates.progress * 100) + "%" : String(Updates.total)
                        size: 12; weight: Theme.wSemibold; rounded: true
                        color: Theme.accent
                        font.features: ({ "tnum": 1 })
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
                        : Updates.repo.length + " Arch · " + Updates.aur.length + " AUR" + (Updates.waitingReview ? " · " + Updates.waitingReview + " to review" : "")
                    shown: updArea.containsMouse
                    below: true
                }
            }
            TrayRow { window: hover.bar; anchors.verticalCenter: parent.verticalCenter }
            IslandStatus { anchors.verticalCenter: parent.verticalCenter; bar: hover.bar; showBluetooth: true }
        }
    }
}
