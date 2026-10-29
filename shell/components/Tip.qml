// A tooltip: a small dark pill above (or below) its parent, after the
// pointer rests 450 ms; once one has shown, neighbours show at once (Emil:
// skip the delay on subsequent hovers). No motion beyond a 120 ms fade.
//
//   Item { HoverHandler { id: h }  Tip { text: "16 threads"; shown: h.hovered } }
import QtQuick
import qs.config

Item {
    id: tip
    property string text
    property bool shown: false
    property bool below: false
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    y: below ? (parent ? parent.height + 6 : 0) : -height - 6
    width: label.implicitWidth + 16
    height: label.implicitHeight + 8
    z: 1000
    visible: opacity > 0.01 && text !== ""

    // Shared across all tips: whether one was shown a moment ago.
    property bool warm: false
    Timer { id: rest; interval: tip.warm ? 0 : 450; onTriggered: tip.opacity = 1 }
    onShownChanged: {
        if (shown) rest.restart();
        else { rest.stop(); opacity = 0; }
    }
    opacity: 0
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(0.11, 0.11, 0.13, 0.98)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)
    }
    Label { id: label; anchors.centerIn: parent; text: tip.text; size: 11; weight: Theme.wMedium; color: Theme.textPrimary }
}
