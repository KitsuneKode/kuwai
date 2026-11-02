// A small ring gauge with its value in the middle and a label under it,
// Apple Watch–style: the arc in a colour, the track faint; amber past 70 %,
// red past 90 %. The arc glides to new values.
//
//   StatRing { value: SystemStats.cpu; label: "CPU" }
import QtQuick
import QtQuick.Shapes
import qs.config

Item {
    id: ring
    property real value: 0               // 0–1
    property string label
    property string text: Math.round(value * 100) + "%"
    property color color: value > 0.9 ? Theme.red : value > 0.7 ? Theme.orange : Theme.accent
    // Load changes colour gradually, not in jumps.
    Behavior on color { ColorAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    property int size: 44
    property real stroke: 4              // a thinner ring for small sizes (the island's 18 px)
    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight

    property real shown: value
    Behavior on shown { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

  Column {
    id: col
    spacing: 4
    Item {
        width: ring.size; height: ring.size
        anchors.horizontalCenter: parent.horizontalCenter
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, 0.1); strokeWidth: ring.stroke; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: ring.size / 2; centerY: ring.size / 2; radiusX: ring.size / 2 - ring.stroke / 2 - 1; radiusY: ring.size / 2 - ring.stroke / 2 - 1; startAngle: -90; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: ring.color; strokeWidth: ring.stroke; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: ring.size / 2; centerY: ring.size / 2; radiusX: ring.size / 2 - ring.stroke / 2 - 1; radiusY: ring.size / 2 - ring.stroke / 2 - 1; startAngle: -90; sweepAngle: 360 * Math.max(0.005, Math.min(1, ring.shown)) }
            }
        }
        // The number morphs digit by digit when it changes (TextMorph, quick).
        TextMorph { visible: ring.text !== ""; anchors.centerIn: parent; text: ring.text; size: 11; weight: Theme.wSemibold; rounded: true; duration: 320; stagger: 25 }
    }
    Label { visible: ring.label !== ""; anchors.horizontalCenter: parent.horizontalCenter; text: ring.label; size: 11; weight: Theme.wMedium; color: Theme.textSecondary }
  }
}
