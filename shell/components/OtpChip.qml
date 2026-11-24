// A one-time code, the hero of its notification: big, spaced, tabular
// ("482 913") with Copy beside it. Dimmed with "may have expired" after ten
// minutes. Hidden while sharing the screen (the card shows nothing of it).
//   OtpChip { item: card.item }
import QtQuick
import qs.config
import qs.components.ui as Ui

Rectangle {
    id: chip
    property string code: ""
    property string spacedCode: code
    property bool stale: false
    property bool hidden: false
    signal copyRequested()
    visible: code !== "" && !hidden
    width: parent ? parent.width : 300
    height: 52
    radius: Theme.r3
    color: Theme.card
    border.width: 1
    border.color: Theme.cardEdge
    Column {
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
        spacing: 0
        Text {
            textFormat: Text.PlainText
            text: chip.spacedCode
            font.family: Theme.fontRounded
            font.pixelSize: Theme.tTitle1
            font.weight: Font.DemiBold
            font.letterSpacing: 2
            font.features: Theme.numeralFeatures(true, true)
            color: chip.stale ? Theme.textTertiary : Theme.textPrimary
        }
        Label {
            visible: chip.stale
            text: "May have expired"
            size: Theme.tCaption; color: Theme.textTertiary
        }
    }
    Ui.Button {
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        height: Theme.sp(30); size: Theme.tSub
        text: "Copy"
        kind: chip.stale ? "secondary" : "primary"
        onClicked: chip.copyRequested()
    }
}
