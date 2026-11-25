// A toggle tile (Control Center style): mark + label, filled with the accent
// while on. For a setting row's on/off use components/Toggle.
//
//   Tile { glyph: "\u{f0176}"; label: "Caffeine"; on: Caffeine.on; onClicked: Caffeine.on = !Caffeine.on }
import QtQuick
import qs.config
import qs.components

Rectangle {
    id: t
    property string glyph
    property string label
    property bool on
    signal clicked()

    // At least 138 × 38; more as its label grows with the Text size.
    implicitHeight: Math.max(38, tileRow.implicitHeight + 2 * Theme.s2)
    implicitWidth: Math.max(138, tileRow.implicitWidth + 2 * Theme.s3)
    radius: Theme.r2
    color: on ? Qt.alpha(Theme.accent, 0.9) : area.containsMouse ? Theme.pillHover : Theme.pill
    scale: area.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    Row {
        id: tileRow
        anchors.centerIn: parent
        spacing: 7
        Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; text: t.glyph; font.family: Theme.fontGlyph; font.pixelSize: 15; color: t.on ? Theme.onAccent : Theme.textPrimary }
        Label { anchors.verticalCenter: parent.verticalCenter; text: t.label; size: Theme.tSub; weight: Theme.wMedium; color: t.on ? Theme.onAccent : Theme.textPrimary }
    }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: t.clicked() }

    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: t.on
    Accessible.name: t.label
    Accessible.onPressAction: t.clicked()
    Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { t.clicked(); e.accepted = true; } }
    FocusRing {}
}
