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
    property string icon: ""
    property string iconStyle: "bold"
    property string title
    property string detail
    property color tone: Theme.orange
    property string action: ""
    property int detailLines: 2
    signal acted()
    readonly property bool stacked: act.visible && n.width - Theme.sp(42) - act.implicitWidth - 24 < Theme.sp(180)

    width: parent ? parent.width : 0
    implicitHeight: stacked ? col.implicitHeight + act.height + 30 : Math.max(Theme.sp(48), col.implicitHeight + 20, act.visible ? act.height + 16 : 0)
    height: implicitHeight
    radius: Theme.r3 - 2
    color: Qt.alpha(tone, Theme.tintNotice)

    Text { visible: n.icon === ""; textFormat: Text.PlainText; x: 14; y: n.stacked ? 10 : (n.height - height) / 2; text: n.glyph; font.family: Theme.fontGlyph; font.pixelSize: Theme.sp(Theme.glyphM); color: n.tone }
    Icon { visible: n.icon !== ""; x: 14; y: n.stacked ? 10 : (n.height - height) / 2; name: n.icon; style: n.iconStyle; size: Theme.sp(Theme.glyphM); color: n.tone }
    Column {
        id: col
        x: Theme.sp(42); y: n.stacked ? 10 : (n.height - implicitHeight) / 2
        width: n.width - x - (act.visible && !n.stacked ? act.width + 24 : 14)
        spacing: 2
        Label { width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: n.title; size: Theme.tBody; weight: Theme.wSemibold }
        Label { width: parent.width; wrapMode: Text.Wrap; maximumLineCount: n.detailLines; elide: Text.ElideRight; text: n.detail; size: Theme.tFootnote; color: Theme.textSecondary; visible: text !== "" }
    }
    Button {
        id: act
        visible: n.action !== ""
        text: n.action; kind: "secondary"
        x: n.stacked ? col.x : n.width - width - 10
        y: n.stacked ? col.y + col.implicitHeight + 10 : (n.height - height) / 2
        height: Theme.sp(28)
        onClicked: n.acted()
    }
    Accessible.role: Accessible.AlertMessage
    Accessible.name: n.title + (n.detail ? ". " + n.detail : "")
}
