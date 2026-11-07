// Liquid glass on the expanded island: light at the edge of the black, not
// a tint over it. A hairline that brightens where the edge faces the pointer,
// a soft inner bevel, a faint sheen at the top (shaders/liquidrim.frag).
// Still when nothing moves (it redraws only as the pointer does); off with
// reduced motion's still light (no pointer follow) and on battery.
//   LiquidRim { anchors.fill: body; radius: 30; light: Qt.point(x, y); strength: k }
import QtQuick
import Quickshell.Services.UPower

ShaderEffect {
    id: rim
    property real radius: 30
    property point light: Qt.point(width / 2, -40)
    property real strength: 1
    property real full: 0                // 1: a floating card, all four corners
    property real ear: 0                 // a notch's concave ears (NotchShape.ear): the line curves out with them
    readonly property vector2d size: Qt.vector2d(width, height)
    readonly property bool onBattery: UPower.onBattery
    visible: strength > 0.01 && width > 40 && !onBattery
    blending: true
    fragmentShader: Qt.resolvedUrl("../shaders/liquidrim.frag.qsb")
}
