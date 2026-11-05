// Something to know, in its tone: a mark, a title, a line of detail and at
// most one action. Orange = needs you; red = broke; green = done; white = info.
//
//   Notice { glyph: "\u{f0026}"; title: "Reboot to finish"; detail: "The kernel changed"; action: "Reboot"; onActed: … }
import QtQuick
import qs.config
import qs.components

Rectangle {
    id: n
    property string glyph
    property string title
    property string detail
    property color tone: Theme.orange
    property string action: ""
    signal acted()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(48, col.implicitHeight + 20)
    height: implicitHeight
    radius: Theme.r3 - 2
    color: Qt.alpha(tone, Theme.tintNotice)

    Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: n.glyph; font.family: Theme.fontGlyph; font.pixelSize: 17; color: n.tone }
    Column {
        id: col
        x: 42; anchors.verticalCenter: parent.verticalCenter
        width: n.width - 42 - (act.visible ? act.width + 24 : 14)
        spacing: 2
        Label { width: parent.width; elide: Text.ElideRight; text: n.title; size: 13; weight: Theme.wSemibold }
        Label { width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: n.detail; size: 11; color: Theme.textSecondary; visible: text !== "" }
    }
    Button {
        id: act
        visible: n.action !== ""
        text: n.action; kind: "secondary"
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        height: 28
        onClicked: n.acted()
    }
    Accessible.role: Accessible.AlertMessage
    Accessible.name: n.title + (n.detail ? ". " + n.detail : "")
}
