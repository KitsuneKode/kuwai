import QtQuick
import Quickshell.Widgets
import qs.config

Item {
    id: mat
    property string level: "regular"
    property real radius: Theme.r4
    property color tint: spec.tint
    property real grain: 0
    readonly property var spec: Theme.materialSpec(level)

    Rectangle {
        anchors.fill: parent
        radius: mat.radius
        color: mat.tint
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, mat.spec.darkRing)
    }

    Rectangle {
        visible: mat.spec.sheen > 0
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, mat.radius - 1)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, mat.spec.sheen) }
            GradientStop { position: Math.min(0.04, 3 / Math.max(1, mat.height)); color: Qt.rgba(1, 1, 1, mat.spec.sheen * 0.5) }
            GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, mat.spec.sheen * 0.15) }
            GradientStop { position: 0.7; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.12) }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, mat.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: mat.spec.rim
    }

    ClippingRectangle {
        visible: mat.grain > 0
        anchors.fill: parent
        radius: mat.radius
        color: "transparent"
        opacity: Math.min(0.05, mat.grain)
        Image {
            anchors.fill: parent
            source: Qt.resolvedUrl("../assets/grain.png")
            fillMode: Image.Tile
            smooth: false
            cache: true
        }
    }
}
