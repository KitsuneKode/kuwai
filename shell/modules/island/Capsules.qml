// Workspace capsules: the active one long and bright, occupied ones dimmer,
// empty ones faint; the long pill slides between them. Click to go there.
// `bar` is the island bar window (activeWs, wsCount, mine).
import QtQuick
import Quickshell.Hyprland
import qs.config

Row {
    id: caps
    required property var bar
    spacing: 4

    Repeater {
        model: caps.bar.wsCount
        Rectangle {
            id: cap
            required property int index
            readonly property int ws: index + 1
            readonly property bool on: ws === caps.bar.activeWs
            readonly property bool used: caps.bar.mine.some(w => w.id === ws && w.toplevels && w.toplevels.values.length > 0)
            anchors.verticalCenter: parent.verticalCenter
            height: 10; radius: 5
            width: on ? 22 : 10
            color: on ? "white" : used ? Qt.rgba(1, 1, 1, capArea.containsMouse ? 0.7 : 0.45) : Qt.rgba(1, 1, 1, capArea.containsMouse ? 0.4 : 0.18)
            Behavior on width { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            MouseArea {
                id: capArea
                anchors.fill: parent
                anchors.margins: -3
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + cap.ws)
            }
        }
    }
}
