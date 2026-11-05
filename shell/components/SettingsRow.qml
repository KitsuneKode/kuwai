// One setting: its name (and a line of detail) on the left, its control on
// the right; a hairline above every row but the first in its group.
//
//   SettingsRow { label: "24-hour time"; Toggle { … } }
import QtQuick
import qs.config

Item {
    id: row
    property string label
    property string detail
    default property alias control: slot.data
    width: parent ? parent.width : 480
    // The detail wraps (up to three lines) and the row grows with it.
    height: Math.max(detail ? 60 : 46, text.implicitHeight + 24)

    Rectangle {
        visible: !row.Positioner.isFirstItem
        x: 14; width: parent.width - 14; height: 1
        color: Qt.rgba(1, 1, 1, 0.07)
    }
    Column {
        id: text
        anchors { left: parent.left; leftMargin: 14; right: slot.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 2
        Label { width: parent.width; elide: Text.ElideRight; text: row.label; size: 13 }
        Label { visible: row.detail !== ""; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; text: row.detail; size: 11; color: Theme.textTertiary }
    }
    Item {
        id: slot
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        width: childrenRect.width
        height: childrenRect.height
    }
}
