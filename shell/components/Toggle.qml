// An on/off switch, Apple's: a 42×26 track that turns green, a white knob
// that slides on the fast spring and stretches a little while pressed.
// The parent applies `toggled()`; `on` is only shown.
//
//   Toggle { on: Settings.clock24; onToggled: Settings.set("clock24", !Settings.clock24) }
import QtQuick
import qs.config

Item {
    id: t
    property bool on: false
    property bool enabled: true
    signal toggled()

    implicitWidth: 42
    implicitHeight: 26
    opacity: enabled ? 1 : 0.4

    Spring { id: k; tier: Theme.springFast; target: t.on ? 1 : 0; Component.onCompleted: settle() }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.tint(Qt.rgba(1, 1, 1, 0.16), Qt.alpha(Theme.green, k.value))
    }
    Rectangle {
        property real stretch: area.pressed ? 5 : 0
        Behavior on stretch { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        width: 22 + stretch
        height: 22
        radius: 11
        y: 2
        x: 2 + (t.width - 4 - width) * k.value
        color: "white"
    }
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -4
        enabled: t.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: t.toggled()
    }
}
