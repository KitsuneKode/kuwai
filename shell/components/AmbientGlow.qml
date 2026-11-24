import QtQuick
import QtQuick.Shapes
import qs.config

Shape {
    id: glow
    property color tint: Theme.accent
    property real radius: Theme.r3
    property bool breathing: false
    property real strength: tint.hslSaturation < 0.25 ? 0.42 : 0.85
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    opacity: breath
    property real breath: 1
    SequentialAnimation on breath {
        running: glow.breathing && glow.visible && !Theme.reduceMotion
        loops: Animation.Infinite
        NumberAnimation { to: 0.62; duration: Theme.breathOutMs * 2; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: Theme.breathOutMs * 2; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) glow.breath = 1
    }
    ShapePath {
        strokeWidth: -1
        fillTransform: PlanarTransform.fromScale(1, 0.24, glow.width * 0.36, glow.height + 4)
        fillGradient: RadialGradient {
            centerX: glow.width * 0.36; centerY: glow.height + 4
            centerRadius: glow.width * 0.62
            focalX: centerX; focalY: centerY
            GradientStop { position: 0; color: Qt.alpha(glow.tint, glow.strength) }
            GradientStop { position: 0.28; color: Qt.alpha(glow.tint, glow.strength * 0.62) }
            GradientStop { position: 0.6; color: Qt.alpha(glow.tint, glow.strength * 0.16) }
            GradientStop { position: 1; color: Qt.alpha(glow.tint, 0) }
        }
        PathRectangle { width: glow.width; height: glow.height; radius: glow.radius }
    }
}
