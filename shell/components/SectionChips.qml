import QtQuick
import qs.config

Row {
    id: chips

    property var model: []
    property string current: ""
    signal picked(string id)

    spacing: 2

    Repeater {
        model: chips.model
        delegate: Rectangle {
            id: sec
            required property var modelData
            required property int index
            readonly property bool on: chips.current === modelData.id
            readonly property int badge: modelData.badge || 0
            width: 30; height: 24; radius: Theme.r2
            color: on ? Theme.wash(3) : secArea.containsMouse ? Theme.wash(1) : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
            Accessible.role: Accessible.PageTab
            Accessible.name: modelData.label + (badge > 0 ? ", " + badge + " unread" : "")
            Accessible.selected: on
            Accessible.onPressAction: chips.picked(sec.modelData.id)
            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: sec.modelData.glyph
                font.family: Theme.fontGlyph; font.pixelSize: 13
                color: sec.on ? Theme.textPrimary : secArea.containsMouse ? Theme.textSecondary : Theme.textTertiary
            }
            Rectangle {
                visible: sec.badge > 0 && !sec.on
                anchors { right: parent.right; top: parent.top; rightMargin: 5; topMargin: 4 }
                width: 6; height: 6; radius: 3
                color: Theme.blue
            }
            MouseArea { id: secArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chips.picked(sec.modelData.id) }
            Tip { text: sec.modelData.label + (sec.badge > 0 ? ", " + sec.badge + " unread" : "") + "  Alt+" + (sec.index + 1); shown: secArea.containsMouse; below: true }
        }
    }
}
