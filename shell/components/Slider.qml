// Fluid Functionalism's "scrubber" slider, horizontal or vertical (a fader).
//
//   ┌──────────────────────────┃─────────────┐
//   │ ☀ Brightness  ▓▓▓▓▓▓▓▓▓▓ ┃        30 % │   36px track, fill to the value,
//   └──────────────────────────┃─────────────┘   a 2px handle line at its edge
//
// Craft, from the FF spec: the fill is glued to the pointer while dragging
// (no spring: direct manipulation); a click on the track springs it to the
// click (moderate spring); outside changes glide there too. The handle line
// grows 2px taller and darkens 25% → 50% → 100% across rest / hover / drag;
// at the minimum a zero offset keeps it visible. The value brightens on
// hover. The hit area runs 8px past each edge. Wheel and two-finger scroll
// step it. `value` is 0..1 (or from..to); the parent applies `moved(v)`.
import QtQuick
import qs.config

Item {
    id: s

    property real value: 0
    property real from: 0
    property real to: 1
    property real stepSize: 0.01
    property bool vertical: false
    property string label
    property string glyph
    property string valueText: Math.round(norm(value) * 100) + "%"
    property color fillColor: Qt.rgba(1, 1, 1, 0.16)
    property bool dim: false                  // muted: the fill goes quiet
    signal moved(real value)

    readonly property bool active: area.pressed
    readonly property bool hot: area.containsMouse || area.pressed

    implicitWidth: vertical ? 44 : 240
    implicitHeight: vertical ? 180 : 36

    function norm(v) { return to === from ? 0 : Math.max(0, Math.min(1, (v - from) / (to - from))); }
    function denorm(f) {
        let v = from + f * (to - from);
        if (stepSize > 0) v = Math.round(v / stepSize) * stepSize;
        return Math.max(Math.min(from, to), Math.min(Math.max(from, to), v));
    }

    // Shown fraction: glued while dragging, sprung otherwise.
    Spring { id: shown; tier: Theme.springModerate; epsilon: 0.001; Component.onCompleted: snap(s.norm(s.value)) }
    onValueChanged: if (!area.pressed) shown.target = norm(value)

    readonly property real length: vertical ? height : width
    readonly property real zeroOffset: 17
    readonly property real fillLen: Math.max(zeroOffset, zeroOffset + (length - zeroOffset) * shown.value)

    Rectangle {
        id: track
        anchors.fill: parent
        radius: s.vertical ? 14 : 12
        color: Qt.rgba(1, 1, 1, s.hot ? 0.08 : 0.065)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.06)
        clip: true
        Behavior on color { ColorAnimation { duration: 80 } }

        Rectangle {
            x: 0
            y: s.vertical ? parent.height - height : 0
            width: s.vertical ? parent.width : s.fillLen
            height: s.vertical ? s.fillLen : parent.height
            radius: track.radius
            color: s.fillColor
            opacity: s.dim ? 0.45 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
        }

        // The handle: a 2px line at the fill's edge.
        Rectangle {
            readonly property real inset: s.hot ? 7 : 8
            x: s.vertical ? inset : s.fillLen - 7
            y: s.vertical ? parent.height - s.fillLen + 5 : inset
            width: s.vertical ? parent.width - inset * 2 : 2
            height: s.vertical ? 2 : parent.height - inset * 2
            radius: 1
            color: Qt.rgba(1, 1, 1, s.active ? 1 : s.hot ? 0.5 : 0.25)
            Behavior on color { ColorAnimation { duration: 80 } }
        }

        // Horizontal: label (and glyph) on the left, value on the right.
        Row {
            visible: !s.vertical
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7
            Text {
                visible: s.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: s.glyph
                font.family: Theme.fontGlyph
                font.pixelSize: 14
                color: Theme.textPrimary
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: s.label
                size: 13
                weight: Theme.wMedium
            }
        }
        Label {
            visible: !s.vertical
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: s.valueText
            size: 13
            rounded: true
            weight: Theme.wMedium
            font.features: ({ "tnum": 1 })
            color: s.hot ? Theme.textPrimary : Theme.textSecondary
            Behavior on color { ColorAnimation { duration: 80 } }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -8                      // hit area 8px past each edge
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        property bool dragged: false

        function fractionAt(mx, my) {
            const p = s.vertical ? (s.height + 8 - my) : (mx - 8);
            return Math.max(0, Math.min(1, (p - s.zeroOffset) / Math.max(1, s.length - s.zeroOffset)));
        }
        onPressed: mouse => { dragged = false; }
        onPositionChanged: mouse => {
            if (!pressed) return;
            dragged = true;
            const f = fractionAt(mouse.x, mouse.y);
            shown.snap(f);                       // glued to the pointer
            s.moved(s.denorm(f));
        }
        onReleased: mouse => {
            if (dragged) { shown.target = s.norm(s.value); return; }
            // A click: spring there.
            const f = fractionAt(mouse.x, mouse.y);
            shown.target = f;
            s.moved(s.denorm(f));
        }
        onWheel: wheel => {
            const d = (wheel.angleDelta.y || -wheel.angleDelta.x) / 120;
            const f = Math.max(0, Math.min(1, s.norm(s.value) + d * Math.max(0.01, s.stepSize / Math.abs(s.to - s.from || 1)) * 5));
            s.moved(s.denorm(f));
        }
    }
}
