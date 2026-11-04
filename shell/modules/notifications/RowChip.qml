// A small pill button on a notification row (its actions, Reply, snooze times).
import QtQuick
import qs.config
import qs.components

Rectangle {
    id: chip
    property string text
    property string glyph: ""
    signal clicked()
    height: 26; radius: 13
    width: chipRow.implicitWidth + 20
    color: chipArea.containsMouse ? Theme.pillHover : Theme.pill
    Accessible.role: Accessible.Button
    Accessible.name: chip.text
    Behavior on color { ColorAnimation { duration: 80 } }
    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 5
        Text { visible: chip.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; text: chip.glyph; font.family: Theme.fontGlyph; font.pixelSize: 12; color: Theme.textPrimary }
        Label { anchors.verticalCenter: parent.verticalCenter; text: chip.text; size: 12; weight: Theme.wMedium }
    }
    MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
}
