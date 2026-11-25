// A small pill button on a notification row (its actions, Reply, snooze times).
import QtQuick
import qs.config
import qs.components

Rectangle {
    id: chip
    property string text
    property string glyph: ""
    property bool filled: false
    signal clicked()
    height: 26; radius: 13
    width: chipRow.implicitWidth + 20
    color: chip.filled
        ? (chipArea.containsMouse ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(1, 1, 1, 0.88))
        : (chipArea.containsMouse ? Theme.pillHover : Theme.pill)
    // The keyboard: Space or ↵ (reached from the row: Space, or S for snooze).
    activeFocusOnTab: visible
    Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { chip.clicked(); e.accepted = true; } }
    FocusRing {}
    Accessible.role: Accessible.Button
    Accessible.name: chip.text
    Accessible.onPressAction: chip.clicked()
    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 5
        Text { textFormat: Text.PlainText; visible: chip.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; text: chip.glyph; font.family: Theme.fontGlyph; font.pixelSize: 12; color: Theme.textPrimary }
        Label { anchors.verticalCenter: parent.verticalCenter; text: chip.text; size: Theme.tSub; weight: Theme.wMedium; color: chip.filled ? Theme.inkOnLight : Theme.textPrimary }
    }
    MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
}
