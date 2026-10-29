// A warning grown out of the island (services/Alerts): a mark in the
// alert's colour, what's wrong, the detail, and a way in. Click to open the
// System panel; the island folds back by itself after a few seconds.
import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: banner
    required property var alert
    required property var bar
    implicitWidth: 440
    implicitHeight: 72
    readonly property color tone: alert && alert.level === "crit" ? Theme.red : Theme.orange

    Rectangle {
        id: mark
        x: 18; anchors.verticalCenter: parent.verticalCenter
        width: 38; height: 38; radius: 19
        color: Qt.alpha(banner.tone, 0.2)
        Text { anchors.centerIn: parent; text: banner.alert ? banner.alert.glyph : ""; font.family: Theme.fontGlyph; font.pixelSize: 19; color: banner.tone }
    }
    Column {
        anchors { left: mark.right; leftMargin: 12; right: go.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 2
        Label { width: parent.width; elide: Text.ElideRight; text: banner.alert ? banner.alert.title : ""; size: 14; weight: Theme.wSemibold }
        Label { width: parent.width; elide: Text.ElideRight; text: banner.alert ? banner.alert.detail : ""; size: 12; color: Theme.textSecondary }
    }
    Rectangle {
        id: go
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        height: 28; radius: 14
        width: goLabel.implicitWidth + 22
        color: goArea.containsMouse ? Qt.alpha(banner.tone, 0.35) : Qt.alpha(banner.tone, 0.2)
        Label { id: goLabel; anchors.centerIn: parent; text: "Details"; size: 12; weight: Theme.wMedium; color: banner.tone }
        MouseArea { id: goArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Alerts.dismiss(); Island.open("system", banner.bar.screenName, "pointer", "island"); } }
    }
}
