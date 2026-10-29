// The island bar (docs/ISLAND.md): the rice's top bar as one island at the top
// centre of each monitor, a notch hanging from the top edge (or a floating
// pill: Settings.islandStyle). On with Settings.bar === "island" (`rice bar
// island`); otherwise it only appears to hold a panel, under Waybar.
//
//   rest     ◉  ● ▮ ● ●  23:29  ▂▄▆ ▭  0:07         (IslandRest: + live activities)
//   hover    app · window / clock · media or rings / workspaces · tray · battery   (IslandHover)
//   panel    calendar, power, launcher, settings, system, theme   (services/Island)
//
// Motion: width and height ride their own springs toward whatever is showing,
// so a change of mind mid-flight turns around without a seam. Growing uses a
// softer spring with a little give (Apple's island: response ≈ 0.42 s,
// damping ≈ 0.78); shrinking is firmer and a touch quicker. The old contents
// fade out early, the new ones fade in late and settle from 97 % scale, so
// the shape leads and the content follows.
//
// Mouse-only navigation: a panel opened from another one shows a back strip
// on top; a right click anywhere in a panel, or the mouse's back button, goes
// back (or closes the first panel). Keys: Esc. A click outside closes.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
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
            readonly property string screenName: modelData ? modelData.name : screen ? screen.name : (Quickshell.screens[0] ? Quickshell.screens[0].name : "")
            readonly property bool notch: Settings.islandStyle !== "floating"
            readonly property int restH: notch ? 32 : 34
            readonly property int top: notch ? 0 : 4
            readonly property real ear: notch ? 9 : 0

            readonly property bool showBar: Settings.bar === "island"
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
            implicitWidth: 900
            implicitHeight: 640
            exclusiveZone: showBar ? restH + top + (notch ? 2 : 6) : 0
            color: "transparent"
            WlrLayershell.namespace: "rice-islandbar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: panelHere ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: Region { item: frame.opacity > 0.01 ? frame : null }

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
            Timer { id: leave; interval: 260; onTriggered: if (!win.hovered) win.grown = false }
            onHoveredChanged: hovered ? intent.restart() : leave.restart()

            readonly property var grow: ({ stiffness: 230, damping: 25 })
            readonly property var shrink: ({ stiffness: 330, damping: 33 })
            Spring { id: m; tier: win.grown ? win.grow : win.shrink; epsilon: 0.001; target: win.grown && !win.panelHere ? 1 : 0 }
            Spring { id: pv; tier: win.panelHere ? win.grow : win.shrink; epsilon: 0.001; target: win.panelHere ? 1 : 0 }

            readonly property real backH: Island.canBack ? 34 : 0
            readonly property size panelSize: panelLoader.item ? Qt.size(panelLoader.item.implicitWidth, panelLoader.item.implicitHeight + backH) : Qt.size(420, 300)
            readonly property size hoverSize: Qt.size(600, showMedia ? 182 : 176)
            readonly property real targetW: panelHere ? panelSize.width : grown ? hoverSize.width : restRow.implicitWidth + 30
            readonly property real targetH: panelHere ? panelSize.height : grown ? hoverSize.height : restH
            Spring { id: sw; tier: win.targetW >= sw.value ? win.grow : win.shrink; epsilon: 0.3; target: win.targetW; Component.onCompleted: settle() }
            Spring { id: sh; tier: win.targetH >= sh.value ? win.grow : win.shrink; epsilon: 0.3; target: win.targetH; Component.onCompleted: settle() }

            // ── Data the parts share ─────────────────────────────────────
            readonly property int activeWs: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 1
            readonly property var mine: Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor === monitor)
            readonly property int wsCount: Math.max(Settings.workspaceCount, ...mine.map(w => w.id), activeWs)
            readonly property var player: Mpris.players.values.find(p => p.playbackState === MprisPlaybackState.Playing) || Mpris.players.values[0] || null
            readonly property bool showMedia: Settings.hoverMedia && player !== null
            property date now: new Date()
            Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: win.now = new Date() }

            Component { id: calendarPanel; CalendarPanel {} }
            Component { id: powerPanel; PowerPanel {} }
            Component { id: launcherPanel; LauncherPanel {} }
            Component { id: settingsPanel; SettingsPanel {} }
            Component { id: systemPanel; SystemPanel {} }
            Component { id: themePanel; ThemePanel {} }

            Elevation {
                target: frame
                radius: Math.min(frame.height / 2, 30)
                strength: (0.25 + 0.75 * Math.max(m.value, pv.value)) * frame.opacity
            }
            Item {
                id: frame
                width: Math.max(0, sw.value) + win.ear * 2
                height: Math.max(0, sh.value)
                x: Math.round((win.width - width) / 2)
                y: win.top
                // Without the bar it is only there for a panel: it fades in as it grows.
                opacity: win.showBar ? 1 : Math.max(0, Math.min(1, pv.value * 2.5))

                HoverHandler { onHoveredChanged: win.hovered = hovered }

                // The island itself: a notch, or a floating black-glass pill.
                NotchShape {
                    visible: win.notch
                    w: Math.max(0, sw.value)
                    h: frame.height
                    ear: win.ear
                    radius: frame.height <= win.restH + 1 ? 14 : 30
                    fill: Qt.rgba(0, 0, 0, 0.94)
                }
                GlassCard {
                    visible: !win.notch
                    anchors.fill: parent
                    radius: Math.min(frame.height / 2, 30)
                    tint: Qt.rgba(0, 0, 0, 0.9)
                }

                Item {
                    id: body
                    x: win.ear
                    width: Math.max(0, sw.value)
                    height: frame.height
                    clip: true

                    // ── At rest ──────────────────────────────────────────
                    IslandRest {
                        id: restRow
                        bar: win
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.round((win.restH - height) / 2)
                        opacity: Math.max(0, 1 - Math.max(m.value, pv.value) * 3)
                        visible: opacity > 0.01
                    }

                    // ── Hovered ──────────────────────────────────────────
                    Loader {
                        id: hoverLoader
                        active: win.grown || m.value > 0.01
                        x: Math.round((body.width - win.hoverSize.width) / 2)
                        width: win.hoverSize.width
                        height: win.hoverSize.height
                        readonly property real k: Math.max(0, Math.min(1, (m.value - 0.25) / 0.5))
                        opacity: k * Math.max(0, 1 - pv.value * 3)
                        scale: 0.97 + 0.03 * k
                        transformOrigin: Item.Top
                        visible: opacity > 0.01
                        sourceComponent: IslandHover { bar: win }
                    }

                    // ── A panel ──────────────────────────────────────────
                    FocusScope {
                        id: panelScope
                        width: win.panelSize.width
                        height: win.panelSize.height
                        x: Math.round((body.width - width) / 2)
                        focus: win.panelHere
                        readonly property real k: Math.max(0, Math.min(1, (pv.value - 0.5) / 0.4))
                        opacity: k
                        scale: 0.97 + 0.03 * k
                        transformOrigin: Item.Top
                        visible: opacity > 0.01 || win.panelHere
                        Keys.onEscapePressed: Island.back()

                        // Back strip: where you came from, one click away.
                        Item {
                            id: backStrip
                            visible: Island.canBack
                            width: parent.width; height: win.backH
                            Rectangle {
                                x: 14; y: 10
                                height: 24; radius: 12
                                width: backRow.implicitWidth + 18
                                color: backArea.containsMouse ? Theme.pillHover : Theme.pill
                                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                                Row {
                                    id: backRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0141}"; font.family: Theme.fontGlyph; font.pixelSize: 14; color: Theme.textSecondary }
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: ({ calendar: "Calendar", power: "Power", launcher: "Search", settings: "Settings", system: "System", theme: "Themes" })[Island.history[Island.history.length - 1]] || "Back"
                                        size: 12; weight: Theme.wMedium; color: Theme.textSecondary
                                    }
                                }
                                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Island.back() }
                            }
                        }
                        Loader {
                            id: panelLoader
                            y: win.backH
                            active: win.panelHere || pv.value > 0.01
                            focus: true
                            sourceComponent: ({ calendar: calendarPanel, power: powerPanel, launcher: launcherPanel, settings: settingsPanel, system: systemPanel, theme: themePanel })[win.shownPanel] || null
                        }
                        // Right click (anywhere a control doesn't take it) or the mouse's back button: back.
                        TapHandler {
                            acceptedButtons: Qt.RightButton | Qt.BackButton
                            onTapped: Island.back()
                        }
                    }
                }
            }
        }
    }
}
