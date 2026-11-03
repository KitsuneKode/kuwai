// Port of shadcn AI Elements: <Suggestion>
// Clickable prompt chip shown after assistant responses or in the welcome state.
// Hover lifts the text; press presses in (0.97).
import QtQuick
import qs.config
import qs.components

Rectangle {
    id: root
    property string text: ""
    property string icon: "lightning"
    signal clicked()

    implicitHeight: 34
    implicitWidth: row.implicitWidth + 24
    radius: 17
    color: area.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, area.containsMouse ? 0.14 : 0.08)
    scale: area.pressed ? 0.97 : 1

    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
    Behavior on border.color { ColorAnimation { duration: Theme.colorMs } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Icon {
            name: root.icon
            size: 14
            color: area.containsMouse ? Theme.textPrimary : Theme.textTertiary
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        }

        Label {
            text: root.text
            size: 13
            weight: Theme.wMedium
            color: area.containsMouse ? Theme.textPrimary : Theme.textSecondary
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
