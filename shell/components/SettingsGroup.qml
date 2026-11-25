// A group of settings rows on one rounded card, with an optional title over
// it (System Settings' inset grouped list). Rows are SettingsRow.
//
//   SettingsGroup { title: "On hover"; SettingsRow { … } SettingsRow { … } }
import QtQuick
import qs.config
import qs.components.ui

Column {
    id: g
    property string title
    default property alias rows: list.data
    width: parent ? parent.width : 480
    spacing: 8

    SectionLabel {
        visible: g.title !== ""
        width: g.width - x
        wrapMode: Text.Wrap
        text: g.title
    }
    Card {
        width: g.width
        flush: true
        Column { id: list; width: parent.width }
    }
}
