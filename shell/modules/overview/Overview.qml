// Mission Control: every workspace of a screen at a glance, and every window
// of the one you're looking at laid out live (Exposé).
//
//   Super+Tab / four-finger pinch in   open · close (global shortcut rice:overview)
//   click a window                     go to it          middle click   close it
//   drag a window onto a space         move it there     click a space  look at it
//   ←→↑↓ Enter                         pick a window     1–9            a space
//   Esc, or click the background       back
//
// One layer per screen (rice-overview: glass via the rice-* layer rule). Only
// the screen you invoke it on shows; the previews are live only while open.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.components

Scope {
    id: root

    property bool open: false
    // Live previews are screen captures: tell kuwai they're ours, so its
    // screen-share privacy doesn't think you're sharing.
    onOpenChanged: if (!open) Hyprland.dispatch("kuwai.capture_hold(false)")
    property string screenName: ""

    function toggle() {
        if (open) {
            open = false;
            return;
        }
        Hyprland.dispatch("kuwai.capture_hold(true)");
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshMonitors();
        const m = Hyprland.focusedMonitor;
        screenName = m ? m.name : (Quickshell.screens[0] ? Quickshell.screens[0].name : "");
        open = true;
    }

    GlobalShortcut {
        appid: "rice"
        name: "overview"
        description: "Mission Control: every workspace and window"
        onPressed: root.toggle()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property bool here: root.open && modelData && modelData.name === root.screenName
            readonly property int activeWs: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 1
            readonly property int base: Math.floor((Math.max(1, activeWs) - 1) / 10) * 10
            property int viewWs: activeWs            // the space whose windows are laid out
            property int picked: 0                   // keyboard selection in the Exposé grid

            visible: here || show.value > 0.01
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "rice-overview"
            WlrLayershell.keyboardFocus: here ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            onHereChanged: if (here) { viewWs = activeWs; picked = 0; keys.forceActiveFocus(); }

            Spring { id: show; tier: win.here ? Theme.surfaceIn : Theme.surfaceOut; target: win.here ? 1 : 0 }

            // Monitor geometry in logical pixels, for placing windows in tiles.
            readonly property var mon: monitor && monitor.lastIpcObject ? monitor.lastIpcObject : ({})
            readonly property real monX: mon.x || 0
            readonly property real monY: mon.y || 0
            readonly property real monW: width
            readonly property real monH: height

            readonly property var spaces: {
                const list = Hyprland.workspaces.values
                    .filter(w => w.id > 0 && w.monitor === win.monitor)
                    .sort((a, b) => a.id - b.id);
                return list;
            }
            function windowsOf(wsId) {
                return Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id === wsId && t.wayland);
            }
            readonly property var shown: windowsOf(viewWs)
            function focusWindow(t) {
                root.open = false;
                Hyprland.dispatch(`hl.dsp.focus({window = 'address:0x${t.address}'})`);
            }
            function closeWindow(t) {
                Hyprland.dispatch(`hl.dsp.window.close({window = 'address:0x${t.address}'})`);
                Qt.callLater(Hyprland.refreshToplevels);
            }
            function goSpace(id) {
                viewWs = id;
                picked = 0;
                Hyprland.dispatch(`hl.dsp.focus({workspace = ${id}})`);
            }
            function nextFree() {
                for (let n = 1; n <= 10; n++)
                    if (!spaces.some(w => w.id === base + n)) return base + n;
                return base + 10;
            }

            // Backdrop: glass over the desktop; clicking it goes back.
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0.02, 0.02, 0.03, 0.42 * show.value)
                MouseArea { anchors.fill: parent; onClicked: root.open = false }
            }

            Item {
                id: keys
                anchors.fill: parent
                focus: win.here
                opacity: Math.min(1, show.value * 1.4)
                scale: 0.97 + 0.03 * show.value
                Keys.onPressed: event => {
                    const n = win.shown.length;
                    const cols = grid.cols;
                    if (event.key === Qt.Key_Escape) root.open = false;
                    else if (event.key === Qt.Key_Right) win.picked = Math.min(n - 1, win.picked + 1);
                    else if (event.key === Qt.Key_Left) win.picked = Math.max(0, win.picked - 1);
                    else if (event.key === Qt.Key_Down) win.picked = Math.min(n - 1, win.picked + cols);
                    else if (event.key === Qt.Key_Up) win.picked = Math.max(0, win.picked - cols);
                    else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && n > 0) win.focusWindow(win.shown[win.picked]);
                    else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) win.goSpace(win.base + (event.key - Qt.Key_0));
                    else if (event.key === Qt.Key_Tab) root.open = false;
                    else return;
                    event.accepted = true;
                }

                // ── Spaces strip ────────────────────────────────────────────
                Row {
                    id: strip
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 56
                    spacing: 18
                    readonly property real tileW: Math.min(220, (win.width - 160) / Math.max(4, win.spaces.length + 1) - 18)
                    readonly property real tileH: tileW * win.monH / Math.max(1, win.monW)

                    Repeater {
                        model: win.spaces
                        delegate: Item {
                            id: tile
                            required property var modelData
                            readonly property bool current: modelData.id === win.viewWs
                            width: strip.tileW
                            height: strip.tileH + 22

                            GlassCard {
                                id: frame
                                width: parent.width
                                height: strip.tileH
                                radius: 10
                                tint: tile.current ? Theme.glassTintElevated : Theme.glassTint
                                clip: true

                                Repeater {
                                    model: win.windowsOf(tile.modelData.id)
                                    delegate: ScreencopyView {
                                        required property var modelData
                                        readonly property var ipc: modelData.lastIpcObject || ({})
                                        readonly property real k: frame.width / Math.max(1, win.monW)
                                        x: ((ipc.at ? ipc.at[0] : 0) - win.monX) * k
                                        y: ((ipc.at ? ipc.at[1] : 0) - win.monY) * k
                                        width: (ipc.size ? ipc.size[0] : 0) * k
                                        height: (ipc.size ? ipc.size[1] : 0) * k
                                        captureSource: win.here ? modelData.wayland : null
                                        live: false
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "transparent"
                                    border.width: tile.current || drop.containsDrag ? 2 : 1
                                    border.color: drop.containsDrag ? Theme.accent : tile.current ? Qt.alpha(Theme.accent, 0.85) : Qt.rgba(1, 1, 1, 0.12)
                                }
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                text: String(tile.modelData.id - win.base)
                                size: 12
                                weight: tile.current ? Theme.wMedium : Theme.wRegular
                                color: tile.current ? Theme.textPrimary : Theme.textSecondary
                            }
                            MouseArea { anchors.fill: frame; onClicked: win.goSpace(tile.modelData.id) }
                            DropArea {
                                id: drop
                                anchors.fill: frame
                                keys: ["kuwai-window"]
                                onDropped: drop => {
                                    const t = drop.source && drop.source.toplevel;
                                    if (t) Hyprland.dispatch(`hl.dsp.window.move({window = 'address:0x${t.address}', workspace = ${tile.modelData.id}, follow = false})`);
                                    Qt.callLater(Hyprland.refreshToplevels);
                                }
                            }
                        }
                    }

                    // New space
                    Item {
                        width: strip.tileW * 0.55
                        height: strip.tileH + 22
                        GlassCard {
                            id: plus
                            width: parent.width
                            height: strip.tileH
                            radius: 10
                            Label { anchors.centerIn: parent; text: "+"; size: 22; color: Theme.textSecondary }
                        }
                        MouseArea { anchors.fill: plus; onClicked: win.goSpace(win.nextFree()) }
                        DropArea {
                            anchors.fill: plus
                            keys: ["kuwai-window"]
                            onDropped: drop => {
                                const t = drop.source && drop.source.toplevel;
                                if (t) Hyprland.dispatch(`hl.dsp.window.move({window = 'address:0x${t.address}', workspace = ${win.nextFree()}, follow = false})`);
                            }
                        }
                    }
                }

                // ── Exposé: the windows of the space you're looking at ──────
                Item {
                    id: grid
                    anchors.top: strip.bottom
                    anchors.topMargin: 36
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 64
                    readonly property int n: win.shown.length
                    readonly property int cols: Math.max(1, Math.ceil(Math.sqrt(n * width / Math.max(1, height) * (win.monH / Math.max(1, win.monW)))))
                    readonly property int rows: Math.max(1, Math.ceil(n / cols))
                    readonly property real cellW: width / cols
                    readonly property real cellH: height / rows

                    Label {
                        anchors.centerIn: parent
                        visible: grid.n === 0
                        text: "No windows on this space"
                        size: 15
                        color: Theme.textTertiary
                    }

                    Repeater {
                        model: win.shown
                        delegate: Item {
                            id: card
                            required property var modelData
                            required property int index
                            readonly property var toplevel: modelData
                            readonly property var ipc: modelData.lastIpcObject || ({})
                            readonly property real aw: Math.max(1, ipc.size ? ipc.size[0] : 16)
                            readonly property real ah: Math.max(1, ipc.size ? ipc.size[1] : 9)
                            readonly property real fit: Math.min((grid.cellW - 40) / aw, (grid.cellH - 64) / ah, 1)
                            readonly property real homeX: (index % grid.cols) * grid.cellW + (grid.cellW - aw * fit) / 2
                            readonly property real homeY: Math.floor(index / grid.cols) * grid.cellH + (grid.cellH - ah * fit - 26) / 2
                            readonly property bool chosen: hover.containsMouse || win.picked === index

                            width: aw * fit
                            height: ah * fit + 26
                            x: homeX
                            y: homeY
                            z: mouse.drag.active ? 10 : 0
                            Drag.active: mouse.drag.active
                            Drag.keys: ["kuwai-window"]
                            Drag.source: card
                            Drag.hotSpot.x: width / 2
                            Drag.hotSpot.y: height / 2

                            Rectangle {
                                id: shot
                                width: parent.width
                                height: parent.height - 26
                                radius: 12
                                color: Qt.rgba(0, 0, 0, 0.25)
                                clip: true
                                scale: card.chosen && !mouse.drag.active ? 1.025 : 1
                                Behavior on scale { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

                                ScreencopyView {
                                    anchors.fill: parent
                                    captureSource: win.here ? card.toplevel.wayland : null
                                    live: win.here
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "transparent"
                                    border.width: card.chosen ? 2 : 1
                                    border.color: card.chosen ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                                }
                            }
                            Label {
                                anchors.top: shot.bottom
                                anchors.topMargin: 8
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(implicitWidth, parent.width)
                                elide: Text.ElideRight
                                text: card.toplevel.title || (card.ipc["class"] || "")
                                size: 12
                                color: card.chosen ? Theme.textPrimary : Theme.textSecondary
                            }

                            MouseArea {
                                id: mouse
                                anchors.fill: shot
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                drag.target: card
                                drag.threshold: 8
                                onReleased: {
                                    if (drag.active) {
                                        card.Drag.drop();
                                        card.x = Qt.binding(() => card.homeX);
                                        card.y = Qt.binding(() => card.homeY);
                                    }
                                }
                                onClicked: event => {
                                    if (event.button === Qt.MiddleButton) win.closeWindow(card.toplevel);
                                    else win.focusWindow(card.toplevel);
                                }
                            }
                            HoverHandler { id: hover; property bool containsMouse: hovered }
                        }
                    }
                }
            }
        }
    }
}
