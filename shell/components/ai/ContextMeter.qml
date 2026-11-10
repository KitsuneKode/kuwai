// How full the chat's context window is (AI Elements <Context>): a small
// ring and a percentage next to Send; hover for the numbers and what happens
// at 75% (older messages get summarised). Accent, then orange past 65%, red past 85%.
import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root

    readonly property real ratio: OllamaService.contextTotal > 0 ? Math.min(1, OllamaService.contextUsed / OllamaService.contextTotal) : 0
    readonly property color tone: ratio > 0.85 ? Theme.red : ratio > 0.65 ? Theme.orange : Theme.accent

    visible: OllamaService.contextUsed > 0
    implicitWidth: row.implicitWidth + 12
    implicitHeight: 30
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: 15
        color: Qt.rgba(1, 1, 1, hover.hovered ? 0.08 : 0)
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
    }
    HoverHandler { id: hover }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Canvas {
            id: ring
            width: 16; height: 16
            anchors.verticalCenter: parent.verticalCenter
            property real shown: root.ratio
            Behavior on shown { NumberAnimation { duration: Theme.glideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            onShownChanged: requestPaint()
            Connections { target: root; function onToneChanged() { ring.requestPaint(); } }
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.lineWidth = 2;
                c.strokeStyle = Qt.rgba(1, 1, 1, 0.14);
                c.beginPath(); c.arc(8, 8, 6, 0, Math.PI * 2); c.stroke();
                c.strokeStyle = root.tone;
                c.lineCap = "round";
                c.beginPath(); c.arc(8, 8, 6, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.02, shown)); c.stroke();
            }
        }
        Label {
            text: Math.round(root.ratio * 100) + "%"
            size: 12
            color: Theme.textTertiary
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // The numbers, on hover.
    Rectangle {
        visible: opacity > 0.01
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: hover.hovered ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        anchors.right: parent.right           // flush right: centred, it ran past the panel's edge
        width: tip.implicitWidth + 24
        height: tip.implicitHeight + 16
        radius: 10
        color: Qt.rgba(0.15, 0.15, 0.18, 0.98)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        z: 50
        Column {
            id: tip
            anchors.centerIn: parent
            spacing: 3
            Label {
                text: OllamaService.contextUsed.toLocaleString(Qt.locale(), "f", 0) + " of "
                      + OllamaService.contextTotal.toLocaleString(Qt.locale(), "f", 0) + " tokens"
                size: 12
                weight: Theme.wMedium
                color: Theme.textPrimary
            }
            Label {
                text: OllamaService.compactNext ? "Summarises before your next message"
                    : OllamaService.summary ? "Earlier messages are summarised" : "Older messages get summarised at 75%"
                size: 11
                color: Theme.textTertiary
            }
        }
    }
}
