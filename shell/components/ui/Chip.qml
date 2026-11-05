// A small tinted label: a state, a count, a kind. Not pressable (that's a Button).
//
//   Chip { text: "Security"; tone: Theme.red; glyph: "\u{f0483}" }
import QtQuick
import qs.config
import qs.components

Rectangle {
    id: chip
    property string text
    property string glyph: ""
    property color tone: Theme.textSecondary

    implicitHeight: 22
    implicitWidth: row.implicitWidth + 16
    radius: height / 2
    color: Qt.alpha(tone, Theme.tintChip)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.s1
        Text {
            visible: chip.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: chip.glyph
            font.family: Theme.fontGlyph; font.pixelSize: 11
            color: chip.tone
        }
        Label { anchors.verticalCenter: parent.verticalCenter; text: chip.text; size: 11; weight: Theme.wMedium; color: chip.tone }
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: chip.text
}
