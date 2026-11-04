// "Connected", drawn in light: around a device's mark an arc closes (the
// link coming up), glowing in its colour, then the closed ring breathes out
// and fades. Whoever owns the moment drives `draw` (0..1, the arc) and
// `ping` (0..1, out and gone).
//
//   LinkRing { anchors.centerIn: platter; width: 64; height: 64; draw: …; ping: … }
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.config

Item {
    id: ring
    property real draw: 0
    property real ping: 0
    property color color: Theme.green
    property real stroke: 2
    property bool glow: true

    visible: draw > 0.001 && ping < 0.999
    opacity: 1 - ping
    scale: 1 + 0.22 * ping

    Shape {
        anchors.fill: parent
        layer.enabled: true; layer.samples: 4
        layer.effect: MultiEffect {
            shadowEnabled: ring.glow
            shadowColor: ring.color
            shadowBlur: 0.7
            shadowOpacity: 0.9
            shadowHorizontalOffset: 0; shadowVerticalOffset: 0
            blurMax: 14
        }
        ShapePath {
            strokeColor: ring.color; strokeWidth: ring.stroke; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.width / 2; centerY: ring.height / 2
                radiusX: ring.width / 2 - ring.stroke - 6; radiusY: ring.height / 2 - ring.stroke - 6
                startAngle: -90; sweepAngle: 360 * ring.draw
            }
        }
    }
}
