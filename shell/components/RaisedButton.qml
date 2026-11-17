// A raised button. The plate is its own layer, so a press squeezes the plate
// to 97% while the words stay put. One outline and one 1px drop. No lit edge,
// no stacked blur. Plain rectangles only: it renders the same in the shell
// and in the password prompt's software renderer (shell-auth vendors this file).
//
//   RaisedButton { text: "Update 31"; onClicked: … }                  primary, the theme's accent
//   RaisedButton { text: "Terminal"; glyph: "\u{f018d}"; kind: "secondary" }
//   RaisedButton { text: "Remove"; kind: "danger"; enabled: … }
import QtQuick
import qs.config

Item {
    id: b
    property string text
    property string glyph: ""
    property string kind: "primary"      // primary · secondary · danger
    property bool enabled: true
    property int size: 13
    signal clicked()

    implicitHeight: 34
    implicitWidth: Math.max(88, row.implicitWidth + 30)

    readonly property bool pressed: area.pressed && enabled
    readonly property bool lit: area.containsMouse && enabled
    readonly property color fill: !enabled ? Qt.rgba(1, 1, 1, 0.08)
        : kind === "danger" ? Theme.red
        : kind === "secondary" ? Qt.rgba(1, 1, 1, 0.12)
        : Theme.accent
    readonly property bool solid: enabled && kind !== "secondary"
    readonly property color ink: !enabled ? Theme.textTertiary
        : kind === "secondary" ? Theme.textPrimary
        : kind === "danger" ? Theme.onDanger
        : Theme.onAccent

    // The plate (everything that moves on press).
    Item {
        id: plate
        anchors.fill: parent
        scale: b.pressed && !Theme.reduceMotion ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

        // One tight drop under the plate. It thins while the plate is pressed.
        Rectangle {
            y: 1
            width: plate.width
            height: plate.height
            radius: height / 2
            visible: b.enabled
            color: Qt.rgba(0, 0, 0, b.pressed ? 0.2 : 0.5)
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        }
        // Fill plus one outline, the same colour all round. No lit top edge.
        Rectangle {
            id: face
            anchors.fill: parent
            radius: height / 2
            color: b.lit && b.solid ? Qt.lighter(b.fill, 1.07) : b.lit ? Qt.rgba(1, 1, 1, 0.18) : b.fill
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            border.width: 1
            border.color: b.solid ? Qt.darker(b.fill, 1.2) : Qt.rgba(1, 1, 1, 0.28)
        }
    }

    // The label: does not move.
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            visible: b.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: b.glyph
            font.family: Theme.fontGlyph; font.pixelSize: b.size
            color: b.ink
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: b.text
            size: b.size
            weight: b.kind === "secondary" ? Theme.wMedium : Theme.wSemibold
            color: b.ink
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: b.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (b.enabled) b.clicked()
    }

    // Keyboard and screen readers: Tab reaches it, Space/Enter presses it.
    activeFocusOnTab: b.enabled
    Accessible.role: Accessible.Button
    Accessible.name: b.text
    Accessible.onPressAction: if (b.enabled) b.clicked()
    Keys.onPressed: e => { if (b.enabled && (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { b.clicked(); e.accepted = true; } }
    FocusRing { cornerRadius: 10 }
}
