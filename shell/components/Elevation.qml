// Elevation for a floating card: layered shadows, not one big smudge. A
// tight contact shadow grounds the edge, a mid one gives form, and a wide
// soft ambient one lifts the card off the page. Put it under the card's
// glass and point `target` at it; `strength` fades all three (0–1).
import QtQuick
import QtQuick.Effects

Item {
    id: e
    property Item target
    property real radius: 22
    property real strength: 1
    anchors.fill: target

    RectangularShadow {
        anchors.fill: parent
        radius: e.radius
        offset.y: 30
        blur: 72
        spread: -14
        color: Qt.rgba(0, 0, 0, 0.42 * e.strength)
    }
    RectangularShadow {
        anchors.fill: parent
        radius: e.radius
        offset.y: 10
        blur: 24
        spread: -6
        color: Qt.rgba(0, 0, 0, 0.30 * e.strength)
    }
    RectangularShadow {
        anchors.fill: parent
        radius: e.radius
        offset.y: 1
        blur: 3
        color: Qt.rgba(0, 0, 0, 0.35 * e.strength)
    }
}
