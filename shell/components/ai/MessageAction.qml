// A small icon button under a message (copy, edit, retry): 28 px target,
// lights on hover, presses in.
import QtQuick
import qs.config
import qs.components

Rectangle {
    id: ab
    property string icon
    signal clicked()
    width: 28; height: 28
    radius: 8
    color: Qt.rgba(1, 1, 1, abArea.containsMouse ? 0.08 : 0)
    scale: abArea.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    Icon { anchors.centerIn: parent; name: ab.icon; size: 15; color: abArea.containsMouse ? Theme.textPrimary : Theme.textTertiary }
    MouseArea { id: abArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ab.clicked() }
}
