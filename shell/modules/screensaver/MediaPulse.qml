import QtQuick
import qs.config

Row {
    id: pulse

    property bool active: false
    property string title: ""
    property real size: Theme.tSub
    property real maxWidth: 400
    property real phase: 0.55
    readonly property bool moving: active && !Theme.reduceMotion
    readonly property real reach: 1 - (1 - phase) * (1 - phase)

    spacing: Math.round(size * 0.7)
    leftPadding: 6
    topPadding: 10

    Item {
        width: Math.round(pulse.size * 1.8)
        height: width
        Rectangle {
            anchors.centerIn: parent
            width: Math.round(pulse.size * 0.5)
            height: width
            radius: width / 2
            color: Qt.alpha(Theme.accent, 0.8)
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.round(parent.width * (0.35 + 0.65 * pulse.reach))
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.5 * (1 - pulse.reach))
        }
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: pulse.title
        elide: Text.ElideRight
        width: Math.min(implicitWidth, pulse.maxWidth)
        font.family: Theme.fontText
        font.pixelSize: pulse.size
        color: Qt.rgba(1, 1, 1, 0.6)
    }
    Timer {
        interval: Theme.saverFrameMs; repeat: true
        running: pulse.moving
        onTriggered: pulse.phase = (pulse.phase + interval / Theme.saverPulseMs) % 1
    }
}
