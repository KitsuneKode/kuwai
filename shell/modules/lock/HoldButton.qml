// A power button on the login screen that acts only when held: a ring fills
// around it while you hold (0.8 s, linear: the deliberate part), drains
// quickly if you let go, and the label says what holding will do. A stray
// click ends nothing.
import QtQuick
import QtQuick.Shapes
import qs.config
import qs.components

Item {
    id: btn
    required property string glyph
    required property string label     // "Restart"
    required property string verb      // "restart": "Hold to restart"
    property color accent: Theme.accent
    signal fired()

    width: 64; height: 70
    property real held: 0
    readonly property bool holding: press.pressed

    NumberAnimation {
        id: fill
        target: btn; property: "held"; to: 1
        onFinished: if (btn.holding) btn.fired()
    }
    NumberAnimation { id: drain; target: btn; property: "held"; to: 0; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    onHoldingChanged: {
        if (holding) { drain.stop(); fill.duration = Math.round(800 * (1 - held)); fill.restart(); }
        else if (held < 1) { fill.stop(); drain.restart(); }
    }

    Item {
        id: disc
        anchors.horizontalCenter: parent.horizontalCenter
        width: 44; height: 44
        scale: btn.holding ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.tint(Qt.rgba(1, 1, 1, over.hovered ? 0.2 : 0.12), Qt.alpha(btn.accent, btn.held * 0.7))
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, over.hovered ? 0.28 : 0.14)
            Behavior on color { enabled: !btn.holding && btn.held === 0; ColorAnimation { duration: Theme.colorMs } }
        }
        Shape {
            anchors.fill: parent
            visible: btn.held > 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: btn.accent; strokeWidth: 2.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 22; centerY: 22; radiusX: 21; radiusY: 21; startAngle: -90; sweepAngle: 360 * btn.held }
            }
        }
        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: Theme.fontGlyph; font.pixelSize: 18
            color: "white"
        }
    }
    Label {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        text: btn.holding || btn.held > 0 ? "Hold to " + btn.verb : btn.label
        size: 12; weight: Theme.wMedium
        color: Qt.rgba(1, 1, 1, btn.holding ? 0.95 : over.hovered ? 0.85 : 0.62)
    }
    HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: press; gesturePolicy: TapHandler.WithinBounds; longPressThreshold: 10 }
}
