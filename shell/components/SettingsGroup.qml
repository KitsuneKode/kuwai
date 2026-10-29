// A group of settings rows on one rounded card, with an optional title over
// it (System Settings' inset grouped list). Rows are SettingsRow.
//
//   SettingsGroup { title: "On hover"; SettingsRow { … } SettingsRow { … } }
import QtQuick
import qs.config

Column {
    id: g
    property string title
    default property alias rows: list.data
    width: parent ? parent.width : 480
    spacing: 8

    Label {
        visible: g.title !== ""
        x: 4
        text: g.title
        size: 12
        weight: Theme.wMedium
        color: Theme.textTertiary
    }
    Rectangle {
        width: g.width
        height: list.implicitHeight
        radius: 12
        color: Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.05)
        Column { id: list; width: parent.width }
    }
}
