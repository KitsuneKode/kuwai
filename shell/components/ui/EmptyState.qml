import QtQuick
import qs.config
import qs.components

Column {
    id: empty
    property string glyph: ""
    property string title: ""
    property string body: ""
    property string actionLabel: ""
    signal actionTriggered()

    spacing: Theme.s2
    width: parent ? parent.width : Theme.sp(260)

    Text {
        visible: empty.glyph !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: empty.glyph
        font.family: Theme.fontGlyph
        font.pixelSize: Theme.tTitle1
        color: Theme.textTertiary
    }

    Label {
        visible: empty.title !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: empty.title
        size: Theme.tHeadline
        weight: Theme.wSemibold
        color: Theme.textPrimary
    }

    Label {
        visible: empty.body !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: empty.body
        size: Theme.tSub
        color: Theme.textSecondary
    }

    Button {
        visible: empty.actionLabel !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        text: empty.actionLabel
        onClicked: empty.actionTriggered()
    }
}
