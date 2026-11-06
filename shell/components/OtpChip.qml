// A one-time code, the hero of its notification: big, spaced, tabular
// ("482 913") with Copy beside it. Dimmed with "may have expired" after ten
// minutes. Hidden while sharing the screen (the card shows nothing of it).
//   OtpChip { item: card.item }
import QtQuick
import qs.config
import qs.services

Rectangle {
    id: chip
    property var item
    readonly property string code: Notifs.otpOf(item)
    readonly property bool stale: !!item && Date.now() - item.time > 10 * 60000
    visible: code !== "" && !Notifs.sharing
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
            text: Notifs.spacedCode(chip.code)
            font.family: Theme.fontRounded
            font.pixelSize: Theme.tTitle1
            font.weight: Font.DemiBold
            font.letterSpacing: 2
            font.features: ({ "tnum": 1 })
            color: chip.stale ? Theme.textTertiary : Theme.textPrimary
        }
        Label {
            visible: chip.stale
            text: "May have expired"
            size: Theme.tCaption; color: Theme.textTertiary
        }
    }
    PillButton {
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        text: "Copy"
        tint: chip.stale ? "transparent" : Theme.accent
        onClicked: Notifs.copyCode(chip.item)
    }
}
