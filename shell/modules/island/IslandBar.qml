// The island bar (docs/ISLAND.md, step 1): the rice's top bar as one island at
// the top centre of each monitor. On only with Settings.bar === "island"
// (`rice bar island`); Waybar stays the bar until then.
//
//   rest    ▮▯▯▯▯  16:29  ▂▄▆ ▭                       (capsules · clock · status)
//   hover   ● Desktop       16:30 Mon, Oct 26        All caught up 🔔
//           ▮▯▯▯▯        ( ◼ ROCK IT · Tokyo Machine ┄┄┄ )        ▂▄▆ ▭
//
// Hover grows it (after a short intent delay, so passing the pointer by does
// nothing) on the moderate spring: height a touch ahead of width, the rest
// row fading out early, the hover layout fading in late. The clock's digits
// roll (RollingNumber, after Skiper's animated number). Click a capsule to go
// to that workspace, the clock or status for the center, the media card for
// Sound. Workspaces come from Hyprland's IPC events: nothing polls.
//
// Panels grow out of it too (services/Island): the clock opens the calendar,
// Super+Escape the power menu. They take the keyboard while open; Esc or a
// click outside folds them back. With Waybar still the bar, the island is
// invisible at rest and appears under Waybar only to hold a panel.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property int restH: 34
            readonly property int hoverW: 780
            // Taller only when the media card is there to fill it.
            readonly property int hoverH: showMedia ? 112 : 78

            // The bar at rest is the island's own setting; panels (calendar,
            // power) use the island either way, under Waybar when it's in charge.
            readonly property bool showBar: Settings.bar === "island"
            readonly property string screenName: modelData ? modelData.name : screen ? screen.name : (Quickshell.screens[0] ? Quickshell.screens[0].name : "")
            readonly property bool panelHere: Island.panel !== "" && Island.screen === screenName
            property string shownPanel: ""
            onPanelHereChanged: {
                if (panelHere) {
                    shownPanel = Island.panel;
                    grown = false;
                    armed = false;
                    arm.restart();
                }
                // Keys open and close it in place: no grow for what a key does.
                if (Island.via === "key") Qt.callLater(() => { sw.settle(); sh.settle(); pv.settle(); });
            }
            Connections {
                target: Island
                function onPanelChanged() { if (win.panelHere) win.shownPanel = Island.panel; }
            }

            anchors.top: true
            implicitWidth: Math.max(hoverW, 520) + 80
            implicitHeight: 600
            exclusiveZone: showBar ? restH + 10 : 0
            color: "transparent"
            WlrLayershell.namespace: "rice-islandbar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: panelHere ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: Region { item: frame.opacity > 0.01 ? frame : null }

            // A click outside closes the panel; armed a beat after opening so
            // the click (or key) that opened it doesn't close it again.
            property bool armed: false
            Timer { id: arm; interval: 160; onTriggered: win.armed = true }
            HyprlandFocusGrab {
                windows: [win]
                active: win.panelHere && win.armed
                onCleared: if (win.panelHere) Island.close()
            }

            // ── Hover, with intent ───────────────────────────────────────
            property bool hovered: false
            property bool grown: false
            Timer { id: intent; interval: Settings.hoverDelay; onTriggered: win.grown = win.hovered && !win.panelHere }
            Timer { id: leave; interval: 160; onTriggered: if (!win.hovered) win.grown = false }
            onHoveredChanged: hovered ? intent.restart() : leave.restart()
            // m: the hover layout; pv: the panel. The frame's width and height
            // ride their own springs toward whichever is showing, so a change
            // of mind mid-flight turns around without a seam.
            Spring { id: m; tier: Theme.springModerate; epsilon: 0.001; target: win.grown && !win.panelHere ? 1 : 0 }
            Spring { id: pv; tier: Theme.springModerate; epsilon: 0.001; target: win.panelHere ? 1 : 0 }
            readonly property size panelSize: panelLoader.item ? Qt.size(panelLoader.item.implicitWidth, panelLoader.item.implicitHeight) : Qt.size(420, 300)
            Spring {
                id: sw; tier: Theme.springModerate; epsilon: 0.3
                target: win.panelHere ? win.panelSize.width : win.grown ? win.hoverW : rest.implicitWidth + 30
                Component.onCompleted: settle()
            }
            Spring {
                id: sh; tier: Theme.springModerate; epsilon: 0.3
                target: win.panelHere ? win.panelSize.height : win.grown ? win.hoverH : win.restH
                Component.onCompleted: settle()
            }
            function lerp(a, b, k) { return a + (b - a) * k; }

            Component { id: calendarPanel; CalendarPanel {} }
            Component { id: powerPanel; PowerPanel {} }
            Component { id: launcherPanel; LauncherPanel {} }

            // ── Data ─────────────────────────────────────────────────────
            readonly property int activeWs: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 1
            readonly property var mine: Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor === monitor)
            readonly property int wsCount: Math.max(Settings.workspaceCount, ...mine.map(w => w.id), activeWs)
            readonly property var player: Mpris.players.values.find(p => p.playbackState === MprisPlaybackState.Playing) || Mpris.players.values[0] || null
            readonly property bool showMedia: Settings.hoverMedia && player !== null
            readonly property var activeWsObj: monitor ? monitor.activeWorkspace : null
            readonly property int activeWindows: activeWsObj && activeWsObj.toplevels ? activeWsObj.toplevels.values.length : 0
            property date now: new Date()
            Timer { interval: Settings.showSeconds ? 1000 : 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: win.now = new Date() }

            Elevation { target: frame; radius: frame.radius; strength: (0.35 + 0.65 * Math.max(m.value, pv.value)) * frame.opacity }
            Item {
                id: frame
                width: Math.max(0, sw.value)
                // Height leads width a touch, so the island reads as dropping open.
                height: Math.max(0, sh.value)
                x: Math.round((win.width - width) / 2)
                y: 4
                // Without the bar it is only there for a panel: it fades in as it grows.
                opacity: win.showBar ? 1 : Math.max(0, Math.min(1, pv.value * 2.5))
                readonly property real radius: Math.min(height / 2, 30)
                clip: true

                HoverHandler { onHoveredChanged: win.hovered = hovered }

                // Apple's island is black: the glass at its darkest.
                GlassCard {
                    anchors.fill: parent
                    radius: frame.radius
                    tint: Qt.rgba(0, 0, 0, 0.9)
                }

                // ── At rest ──────────────────────────────────────────────
                Row {
                    id: rest
                    anchors.centerIn: parent
                    spacing: 14
                    opacity: Math.max(0, 1 - Math.max(m.value, pv.value) * 3)
                    visible: opacity > 0.01
                    Capsules { bar: win; visible: Settings.restWorkspaces; anchors.verticalCenter: parent.verticalCenter }
                    IslandClock {
                        now: win.now; anchors.verticalCenter: parent.verticalCenter; size: 14
                        // Handlers, not a MouseArea: a Row would lay a MouseArea out as a child.
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Island.toggle("calendar", win.screenName, "pointer") }
                    }
                    IslandStatus {
                        visible: Settings.restStatus; anchors.verticalCenter: parent.verticalCenter
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Notifs.toggleCenter("controls", "pointer") }
                    }
                }

                // ── A panel ──────────────────────────────────────────────
                FocusScope {
                    width: win.panelSize.width
                    height: win.panelSize.height
                    x: Math.round((frame.width - width) / 2)
                    focus: win.panelHere
                    opacity: Math.max(0, Math.min(1, (pv.value - 0.55) / 0.35))
                    visible: opacity > 0.01 || win.panelHere
                    Keys.onEscapePressed: Island.close()
                    Loader {
                        id: panelLoader
                        active: win.panelHere || pv.value > 0.01
                        focus: true
                        sourceComponent: ({ calendar: calendarPanel, power: powerPanel, launcher: launcherPanel })[win.shownPanel] || null
                    }
                }

                // ── Hovered ──────────────────────────────────────────────
                Item {
                    width: win.hoverW
                    height: win.hoverH
                    x: Math.round((frame.width - width) / 2)
                    opacity: Math.max(0, Math.min(1, (m.value - 0.5) / 0.4)) * Math.max(0, 1 - pv.value * 3)
                    visible: opacity > 0.01

                    Column {
                        anchors { left: parent.left; leftMargin: 28; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        Row {
                            spacing: 7
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: Theme.green }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                // Numbered workspaces read "Workspace 3"; named ones keep their name.
                                text: !win.activeWsObj ? "Desktop"
                                    : /^\d+$/.test(win.activeWsObj.name || "") || !win.activeWsObj.name ? "Workspace " + win.activeWs
                                    : win.activeWsObj.name
                                size: 13
                                weight: Theme.wMedium
                            }
                            Label {
                                visible: win.activeWsObj !== null
                                anchors.verticalCenter: parent.verticalCenter
                                text: win.activeWindows ? "· " + win.activeWindows + (win.activeWindows === 1 ? " window" : " windows") : "· empty"
                                size: 12
                                color: Theme.textTertiary
                            }
                        }
                        Capsules { bar: win }
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: win.showMedia ? 12 : Math.round((win.hoverH - height) / 2)
                        spacing: 8
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 9
                            IslandClock {
                                now: win.now; anchors.verticalCenter: date.verticalCenter; size: 22
                                // Handlers, not a MouseArea: a Row would lay a MouseArea out as a child.
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Island.toggle("calendar", win.screenName, "pointer") }
                            }
                            Label { id: date; text: Qt.formatDate(win.now, "ddd, MMM d"); size: 14; color: Theme.textSecondary }
                        }
                        // Now playing: art, title, artist, a quiet waveform.
                        Rectangle {
                            visible: win.showMedia
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 360; height: 52; radius: 16
                            color: Qt.rgba(1, 1, 1, mediaArea.containsMouse ? 0.10 : 0.06)
                            ClippingRectangle {
                                id: art
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                width: 38; height: 38; radius: 9
                                color: Qt.rgba(1, 1, 1, 0.08)
                                Image { anchors.fill: parent; source: win.player ? (win.player.trackArtUrl || "") : ""; sourceSize: Qt.size(76, 76); fillMode: Image.PreserveAspectCrop; asynchronous: true }
                            }
                            Column {
                                anchors { left: art.right; leftMargin: 10; right: wave.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                spacing: 1
                                Label { width: parent.width; elide: Text.ElideRight; text: win.player ? (win.player.trackTitle || "Nothing playing").toUpperCase() : ""; size: 12; weight: Theme.wSemibold; extraTracking: 0.3 }
                                Label { width: parent.width; elide: Text.ElideRight; text: win.player ? (win.player.trackArtist || win.player.identity || "") : ""; size: 11; color: Theme.textTertiary }
                            }
                            Row {
                                id: wave
                                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                spacing: 3
                                Repeater {
                                    model: 12
                                    Rectangle {
                                        required property int index
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 2; radius: 1
                                        height: 3
                                        color: Theme.textTertiary
                                        SequentialAnimation on height {
                                            running: win.grown && win.player && win.player.isPlaying && !Theme.reduceMotion
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 4 + ((index * 7) % 11); duration: 260 + (index % 4) * 70; easing.type: Easing.InOutSine }
                                            NumberAnimation { to: 3; duration: 260 + (index % 3) * 80; easing.type: Easing.InOutSine }
                                        }
                                    }
                                }
                            }
                            MouseArea { id: mediaArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.toggleCenter("sound", "pointer") }
                        }
                    }

                    Column {
                        anchors { right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Row {
                            anchors.right: parent.right
                            spacing: 7
                            Label { anchors.verticalCenter: parent.verticalCenter; text: Notifs.unread ? Notifs.unread + " new" : "All caught up"; size: 13; weight: Theme.wMedium }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: Notifs.dnd ? "\u{f009b}" : "\u{f009a}"; font.family: Theme.fontGlyph; font.pixelSize: 14; color: Theme.textSecondary }
                        }
                        IslandStatus { anchors.right: parent.right }
                    }
                    MouseArea {
                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                        width: 200
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifs.toggleCenter(Notifs.unread ? "notifications" : "controls", "pointer")
                    }
                }
            }
        }
    }
}
