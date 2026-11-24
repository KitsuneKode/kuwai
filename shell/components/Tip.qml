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
import QtQuick.Window
import Quickshell
import qs.config

Item {
    id: tip
    property string text
    property bool shown: false
    property bool below: false
    readonly property bool eligible: shown && visible && text.trim() !== "" && parent !== null
    // Shared across all tips (config/TipClock): one showing, or one just
    // closed, means this one shows at once. (A per-tip flag was never set.)
    property bool counted: false
    function count(on) {
        if (on && !counted) { counted = true; TipClock.showing++; }
        else if (!on && counted) { counted = false; TipClock.showing = Math.max(0, TipClock.showing - 1); TipClock.lastHidden = Date.now(); }
    }
    onKChanged: count(k > 0.5)
    Component.onDestruction: count(false)

    width: 0
    height: 0
    property real k: 0               // 0 hidden → 1 shown
    Behavior on k { NumberAnimation { duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    Timer { id: rest; interval: Theme.tipMs; onTriggered: if (tip.eligible) tip.k = 1 }
    onEligibleChanged: {
        if (eligible) { if (TipClock.warm()) k = 1; else rest.restart(); }
        else { rest.stop(); k = 0; }
    }

    function availableTextWidth(shellScreen, nativeScreen) {
        const margins = 2 * Theme.s4;
        const padding = 2 * Theme.s2;
        // An output can briefly report empty geometry. Reserve enough width
        // for readable text before trusting a reported screen size.
        const minimum = margins + padding + 2 * Theme.s5;
        for (const screen of [shellScreen, nativeScreen]) {
            if (screen && Number.isFinite(screen.width) && screen.width >= minimum)
                return Math.min(Theme.panelS, screen.width - margins) - padding;
        }
        return Theme.panelS - padding;
    }

    // The popup exists only while it shows: a window per tooltip, built up
    // front, was dozens of idle windows (every workspace pill has one, and the
    // pills are rebuilt as workspaces change).
    LazyLoader {
        active: tip.k > 0 && tip.parent !== null
        PopupWindow {
            id: pop
            objectName: "tooltip-popup"
            visible: tip.k > 0.01 && tip.parent !== null
            color: "transparent"
            anchor.item: tip.parent
            anchor.edges: tip.below ? Edges.Bottom : Edges.Top
            anchor.gravity: tip.below ? Edges.Bottom : Edges.Top
            anchor.margins.top: tip.below ? 6 : 0
            anchor.margins.bottom: tip.below ? 0 : 6
            readonly property real textWidth: tip.availableTextWidth(tip.QsWindow.window?.screen, tip.Window.window?.screen)
            implicitWidth: label.width + 2 * Theme.s2
            implicitHeight: Math.ceil(label.height) + 2 * Theme.s1
            mask: Region {}

            Rectangle {
                width: pop.implicitWidth
                height: pop.implicitHeight
                radius: Math.min(Theme.r3, height / 2)
                opacity: tip.k
                y: Theme.reduceMotion ? 0 : (1 - tip.k) * (tip.below ? -3 : 3)
                color: Qt.rgba(0.11, 0.11, 0.13, 0.98)
                border.width: 1
                border.color: Theme.edge(1)
                // Measure the widest unwrapped line independently of elision.
                Label {
                    id: naturalText
                    visible: false
                    text: tip.text
                    size: label.size
                    weight: label.weight
                }
                Label {
                    id: label
                    objectName: "tooltip-label"
                    anchors.centerIn: parent
                    width: Math.min(Math.ceil(naturalText.implicitWidth), pop.textWidth)
                    wrapMode: Text.Wrap
                    maximumLineCount: 6
                    elide: Text.ElideRight
                    text: tip.text
                    size: Theme.tSub
                    weight: Theme.wMedium
                    color: Theme.textPrimary
                }
            }
        }
    }
}
