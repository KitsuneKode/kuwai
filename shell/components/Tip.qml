// A tooltip: a small dark pill above (or below) its parent, after the
// pointer rests 450 ms; once one has shown, neighbours show at once (Emil:
// skip the delay on subsequent hovers). No motion beyond a 120 ms fade and a
// 3 px drift toward its place.
//
//   Item { HoverHandler { id: h }  Tip { text: "16 threads"; shown: h.hovered } }
//
// It's its own popup surface (xdg_popup, made while it shows), anchored to the parent: it can sit
// outside the island's shape without the island growing or clipping it, and
// it never takes the pointer (empty input region).
import QtQuick
import Quickshell
import qs.config

Item {
    id: tip
    property string text
    property bool shown: false
    property bool below: false
    // Shared feel across all tips: whether one was shown a moment ago.
    property bool warm: false

    width: 0
    height: 0
    property real k: 0               // 0 hidden → 1 shown
    Behavior on k { NumberAnimation { duration: 120; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    Timer { id: rest; interval: tip.warm ? 0 : Theme.tipMs; onTriggered: tip.k = 1 }
    onShownChanged: {
        if (shown && text !== "") rest.restart();
        else { rest.stop(); k = 0; }
    }

    // The popup exists only while it shows: a window per tooltip, built up
    // front, was dozens of idle windows (every workspace pill has one, and the
    // pills are rebuilt as workspaces change).
    LazyLoader {
        active: tip.k > 0 && tip.parent !== null
        PopupWindow {
            id: pop
            visible: tip.k > 0.01 && tip.parent !== null
            color: "transparent"
            anchor.item: tip.parent
            anchor.edges: tip.below ? Edges.Bottom : Edges.Top
            anchor.gravity: tip.below ? Edges.Bottom : Edges.Top
            anchor.margins.top: tip.below ? 6 : 0
            anchor.margins.bottom: tip.below ? 0 : 6
            implicitWidth: label.implicitWidth + 16
            implicitHeight: label.implicitHeight + 8
            mask: Region {}

            Rectangle {
                width: pop.implicitWidth
                height: pop.implicitHeight
                radius: height / 2
                opacity: tip.k
                y: (1 - tip.k) * (tip.below ? -3 : 3)
                color: Qt.rgba(0.11, 0.11, 0.13, 0.98)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                Label { id: label; anchors.centerIn: parent; text: tip.text; size: 11; weight: Theme.wMedium; color: Theme.textPrimary }
            }
        }
    }
}
