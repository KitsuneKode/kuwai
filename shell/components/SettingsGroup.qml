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
    default property alias rows: list.body
    width: parent ? parent.width : 480
    spacing: 8

    SectionLabel {
        visible: g.title !== ""
        text: g.title
    }
    Card {
        id: list
        width: g.width
        flush: true
    }
}
