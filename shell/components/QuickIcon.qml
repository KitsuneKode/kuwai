// A quick switch in the island's hover row: a glyph that's dim when off and
// lit (in its tone) when on, with a hover disc, a tooltip and keyboard /
// screen-reader support.
//
//   QuickIcon { glyph: "\u{f0176}"; on: Caffeine.on; tone: Theme.yellow
//               tip: "Caffeine"; onClicked: Caffeine.toggle() }
import QtQuick
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
    signal clicked()
    signal wheel(int steps)

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
        onClicked: q.clicked()
        onWheel: w => { const s = w.angleDelta.y > 0 ? 1 : w.angleDelta.y < 0 ? -1 : 0; if (s) q.wheel(s); }
    }
    Tip { text: q.tip; shown: area.containsMouse; below: true }
    FocusRing { cornerRadius: 13; gap: 1 }
}
