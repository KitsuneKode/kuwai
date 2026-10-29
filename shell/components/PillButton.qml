// A capsule button on glass: optional glyph + label. Presses in on
// pointer-down; `tint` fills it with a colour when it represents an "on" state.
//
//   PillButton { glyph: "\u{f0594}"; text: "Do Not Disturb"; tint: on ? "#5e5ce6" : "transparent" }
import QtQuick
import qs.config

Rectangle {
    id: pill

    property string text
    property string glyph
    property color tint: "transparent"
    readonly property bool tinted: tint.a > 0
    signal clicked()

    height: 30
    radius: 15
    width: row.implicitWidth + 22
    color: tinted ? Qt.alpha(tint, area.containsMouse ? 0.95 : 0.85)
         : area.containsMouse ? Theme.pillHover : Theme.pill
    scale: area.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            visible: pill.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: pill.glyph
            font.family: Theme.fontGlyph
            font.pixelSize: 13
            color: Theme.textPrimary
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.text
            size: 12
            weight: Theme.wSemibold
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.clicked()
    }
}
