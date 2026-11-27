import QtQuick
import qs.config

Row {
    id: chip

    property string glyph: ""
    property string text: ""
    property int size: Theme.tLockLine
    property int weight: Theme.wMedium
    property color color: Theme.lockTint(Theme.accent)
    property real maxWidth: 0

    spacing: Math.max(Theme.s1, Math.round(size * Theme.lockChipGap))

    Text {
        id: mark
        visible: chip.glyph !== ""
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: chip.glyph
        font.family: Theme.fontGlyph
        font.pixelSize: Math.round(chip.size * Theme.textScale)
        color: chip.color
    }
    Label {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.text
        size: chip.size; weight: chip.weight
        color: chip.color
        elide: Text.ElideRight
        width: chip.maxWidth > 0 ? Math.min(implicitWidth, Math.max(0, chip.maxWidth - (mark.visible ? mark.width + chip.spacing : 0))) : implicitWidth
    }
}
