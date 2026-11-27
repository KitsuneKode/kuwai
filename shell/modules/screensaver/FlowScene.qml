import QtQuick
import qs.config

Item {
    id: scene
    property bool running: true
    readonly property bool moving: running && !Theme.reduceMotion
    readonly property real period: Math.PI * 2 / 0.005
    property real t: Math.random() * period

    ShaderEffect {
        anchors.fill: parent
        property color accent: Theme.accent
        property vector2d size: Qt.vector2d(width, height)
        property real t: scene.t
        fragmentShader: Qt.resolvedUrl("../../shaders/flow.frag.qsb")
    }
    Timer {
        interval: Theme.saverFrameMs; repeat: true
        running: scene.moving
        onTriggered: scene.t = (scene.t + interval / 1000) % scene.period
    }
}
