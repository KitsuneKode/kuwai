// Workspace pills: small dots, and the workspace you're on stands up as a
// taller pill in the theme's colour (a little wider, mostly taller). Moving
// between workspaces, the old one settles back into a dot as the new one
// rises, both on a spring. Occupied workspaces are brighter dots than empty
// ones. Click to go there; scroll on them to step through.
// `bar` is the island bar window (activeWs, wsCount, mine).
import QtQuick
import Quickshell.Hyprland
import qs.config
import qs.components

Row {
    id: caps
    required property var bar
    property real scale: 1                // 1 at rest, larger in the expanded island
    spacing: 5 * scale
    height: 18 * scale

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => Hyprland.dispatch("workspace " + (event.angleDelta.y > 0 ? "m-1" : "m+1"))
    }

    Repeater {
        model: caps.bar.wsCount
        Item {
            id: cap
            required property int index
            readonly property int ws: index + 1
            readonly property bool on: ws === caps.bar.activeWs
            readonly property bool used: caps.bar.mine.some(w => w.id === ws && w.toplevels && w.toplevels.values.length > 0)
            width: 8 * caps.scale
            height: caps.height

            Spring { id: grow; tier: ({ stiffness: 420, damping: 30 }); target: cap.on ? 1 : 0; Component.onCompleted: settle() }
            Rectangle {
                anchors.centerIn: parent
                width: (6 + 2 * grow.value) * caps.scale
                height: (6 + 10 * grow.value) * caps.scale
                radius: width / 2
                color: Qt.tint(cap.used ? Qt.rgba(1, 1, 1, capArea.containsMouse ? 0.75 : 0.5)
                                        : Qt.rgba(1, 1, 1, capArea.containsMouse ? 0.45 : 0.2),
                               Qt.alpha(Theme.accent, Math.max(0, Math.min(1, grow.value))))
            }
            MouseArea {
                id: capArea
                anchors.fill: parent
                anchors.margins: -2
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + cap.ws)
            }
        }
    }
}
