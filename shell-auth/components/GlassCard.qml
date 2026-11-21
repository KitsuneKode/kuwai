import QtQuick
import qs.config

Item {
    id: card
    property real radius: height / 2.9
    property color tint: Theme.glassTint

    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: card.tint
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.55)
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, card.radius - 1)
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.20) }
            GradientStop { position: Math.min(0.04, 3 / Math.max(1, card.height)); color: Qt.rgba(1, 1, 1, 0.10) }
            GradientStop { position: 0.4;  color: Qt.rgba(1, 1, 1, 0.03) }
            GradientStop { position: 0.7;  color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, 0.12) }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, card.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.07)
    }
}
