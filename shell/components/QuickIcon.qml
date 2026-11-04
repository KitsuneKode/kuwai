// A quick switch in the island's hover row: a glyph that's dim when off and
// lit (in its tone) when on, with a hover disc, a tooltip and keyboard /
// screen-reader support.
//
//   QuickIcon { glyph: "\u{f0176}"; on: Caffeine.on; tone: Theme.yellow
//               tip: "Caffeine"; onClicked: Caffeine.toggle() }
import QtQuick
import QtQuick.Shapes
import qs.config

Item {
    id: q
    property string glyph
    property string glyphOff: ""          // a different glyph when off (a muted speaker)
    property bool on: false
    property color tone: Theme.textPrimary
    property color offTone: Theme.textTertiary
    property string tip: ""
    property real glyphSize: 15
    property bool holdable: false          // press and hold (or right-click): held()
    property bool badge: false             // something else needs a look (a dot)
    property color badgeTone: Theme.red
    signal clicked()
    signal held()
    signal wheel(int steps)
    // The hold's progress: a ring fills while you hold (slow and linear,
    // you're deciding), snaps back the moment you let go.
    property real holdT: 0
    NumberAnimation { id: holdFill; target: q; property: "holdT"; from: 0; to: 1; duration: 350; easing.type: Easing.Linear }
    NumberAnimation { id: holdBack; target: q; property: "holdT"; to: 0; duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }

    width: 26; height: 26
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: q.tip
    Accessible.onPressAction: q.clicked()
    Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { q.clicked(); e.accepted = true; } }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        // A tinted disc only when it's lit in a colour (white glyphs don't need one).
        color: area.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : q.on && !Qt.colorEqual(q.tone, Theme.textPrimary) ? Qt.alpha(q.tone, 0.14) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
    }
    Text {
        anchors.centerIn: parent
        text: !q.on && q.glyphOff !== "" ? q.glyphOff : q.glyph
        font.family: Theme.fontGlyph
        font.pixelSize: q.glyphSize
        color: q.on ? q.tone : (area.containsMouse ? Theme.textSecondary : q.offTone)
        scale: area.pressed ? 0.88 : 1
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -3
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        pressAndHoldInterval: 350
        onPressed: m => { if (q.holdable && m.button === Qt.LeftButton && !Theme.reduceMotion) { holdBack.stop(); holdFill.restart(); } }
        onReleased: { holdFill.stop(); holdBack.restart(); }
        onCanceled: { holdFill.stop(); holdBack.restart(); }
        // A press that became a hold doesn't also click (MouseArea's rule).
        onPressAndHold: { if (q.holdable) { holdFill.stop(); holdBack.restart(); q.held(); } }
        onClicked: m => { if (m.button === Qt.RightButton || (m.modifiers & Qt.ControlModifier)) { if (q.holdable) q.held(); } else q.clicked(); }
        onWheel: w => { const s = w.angleDelta.y > 0 ? 1 : w.angleDelta.y < 0 ? -1 : 0; if (s) q.wheel(s); }
    }
    // The hold ring, around the glyph.
    Shape {
        anchors.fill: parent
        visible: q.holdT > 0.01
        layer.enabled: true; layer.samples: 4
        ShapePath {
            strokeColor: Qt.rgba(1, 1, 1, 0.85); strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: q.width / 2; centerY: q.height / 2; radiusX: q.width / 2 - 1.5; radiusY: q.height / 2 - 1.5; startAngle: -90; sweepAngle: 360 * q.holdT }
        }
    }
    // Another switch is in a non-default state: a small dot, top right.
    Rectangle {
        visible: q.badge
        width: 6; height: 6; radius: 3
        x: q.width - 7; y: 1
        color: q.badgeTone
        border.width: 1.5; border.color: "black"
    }
    Tip { text: q.tip; shown: area.containsMouse && q.holdT === 0; below: true }
    FocusRing { cornerRadius: 13; gap: 1 }
}
