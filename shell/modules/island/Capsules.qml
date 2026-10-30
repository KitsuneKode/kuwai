// Workspace pills, as in the reference: equal-width capsules side by side;
// the one you're on stands taller in the theme's colour with a soft glow,
// occupied ones are a quiet tint, empty ones darker still. The height rides
// a spring with a little give, so moving between workspaces reads as one
// pill rising while the other settles.
//
// The special (hidden, scratchpad) workspace shows as an extra ring that
// pops in on a bouncier spring while it's open, and the others dim behind
// it: it sits on top of your workspace, not beside it.
//
// Click to go there; scroll to step through. Hovering here never expands
// the island (`hovered`), so the pills stay clickable.
// `bar` is the island bar window (activeWs, wsCount, mine, special).
import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland
import qs.config
import qs.components

Row {
    id: caps
    required property var bar
    property real scale: 1
    readonly property bool hovered: hover.hovered
    spacing: 4 * scale
    height: 20 * scale

    HoverHandler { id: hover }
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
            opacity: caps.bar.special ? 0.45 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

            Spring { id: grow; tier: ({ stiffness: 520, damping: 26 }); target: cap.on ? 1 : 0; Component.onCompleted: settle() }
            readonly property real g: Math.max(0, Math.min(1.15, grow.value))
            RectangularShadow {
                anchors.fill: pill
                radius: pill.radius
                blur: 10
                spread: 1
                color: Qt.alpha(Theme.accent, 0.55 * Math.max(0, Math.min(1, grow.value)))
                visible: grow.value > 0.02
            }
            Rectangle {
                id: pill
                anchors.centerIn: parent
                // Inactive ones a little narrower; the current one widens as it rises.
                width: (6 + 2 * Math.min(1, cap.g)) * caps.scale
                height: (13 + 5 * cap.g) * caps.scale
                radius: width / 2
                color: Qt.tint(Qt.alpha(Theme.accent, cap.used ? (capArea.containsMouse ? 0.6 : 0.42) : (capArea.containsMouse ? 0.4 : 0.22)),
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

    // The special workspace: a ring that pops in.
    Item {
        visible: special.value > 0.01
        width: 12 * caps.scale * Math.min(1, special.value)
        height: caps.height
        Spring { id: special; tier: ({ stiffness: 380, damping: 16 }); target: caps.bar.special ? 1 : 0 }
        Rectangle {
            anchors.centerIn: parent
            width: 12 * caps.scale; height: 12 * caps.scale
            radius: width / 2
            scale: Math.max(0, special.value)
            color: "transparent"
            border.width: 2
            border.color: Theme.accent
            Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: Theme.accent }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Hyprland.dispatch("togglespecialworkspace")
        }
    }
}
