// Agents at work (kittymux), as their marks stacked one over the next, the
// first on top (three at most, then "+2"). One blocked on you (an unread
// needs-you event) comes first, ringed in orange. Resting on it, the stack fans
// a little apart: there's more than one in there.
//
//   ✳◐◑ +2     click: the island grows into every agent (AgentsPanel: kitty
//              panes and T3 threads, the model each runs, what it asks)
//              right-click: straight to the one that needs you most
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: stack
    property var bar
    readonly property var waiting: Kittymux.attention.filter(e => e.severity === "needs-you")
        .map(e => ({ agent: e.agent, title: Kittymux.clean(e.tab || e.title), where: "", status: "needs you", needs: true, event: e.id }))
    // An agent kittymux reads as waiting (agents.json state) with no unread
    // event for its pane (it asked before the inbox caught it, or the event was
    // read): it's still asking, so it leads too. It was left out of the stack.
    readonly property var waitingPanes: Kittymux.running.filter(r => r.needs
        && !Kittymux.attention.some(e => e.severity === "needs-you" && String(e.pid) === String(r.pid) && String(e.w) === r.w))
    readonly property var list: waiting.concat(waitingPanes, Kittymux.working)
    readonly property int needN: waiting.length + waitingPanes.length
    readonly property int shown: Math.min(3, list.length)
    readonly property bool many: list.length > 1
    readonly property bool hovered: hover.hovered
    // Kept for IslandRest's marksHovered: the panel now answers in the island itself.
    readonly property bool open: Island.panel === "agents"

    property real step: hover.hovered && many && !open ? 10 : 8
    Behavior on step { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.microMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    readonly property int markSize: 13
    implicitWidth: shown ? markSize + (shown - 1) * step + (list.length > 3 ? moreLabel.implicitWidth + 4 : 0) : 0
    implicitHeight: 16

    Repeater {
        model: stack.shown
        Item {
            required property int index
            readonly property var a: stack.list[index] || null
            x: index * stack.step
            z: stack.shown - index
            anchors.verticalCenter: parent.verticalCenter
            width: stack.markSize; height: stack.markSize
            // Over the one behind it: a ring of the island's black between them.
            Rectangle {
                visible: stack.many || (!!parent.a && !!parent.a.needs)
                anchors.centerIn: parent
                width: parent.width + 4; height: width; radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.94)
                border.width: parent.a && parent.a.needs ? 1.5 : 0
                border.color: Theme.orange
            }
            Image {
                id: mark
                anchors.fill: parent
                sourceSize: Qt.size(26, 26)
                source: parent.a ? Kittymux.brand(parent.a.agent) : ""
                visible: status === Image.Ready
                opacity: stack.open ? 0.35 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
            }
            Text {
                visible: !mark.visible
                anchors.centerIn: parent
                text: "\u{f06a9}"; font.family: Theme.fontGlyph; font.pixelSize: 13
                color: Theme.textSecondary
            }
        }
    }
    Label {
        id: moreLabel
        visible: stack.list.length > 3
        x: stack.markSize + (stack.shown - 1) * stack.step + 4
        anchors.verticalCenter: parent.verticalCenter
        text: "+" + (stack.list.length - 3)
        size: 11; weight: Theme.wSemibold; rounded: true
        color: Theme.textSecondary
    }

    HoverHandler { id: hover; margin: 6; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (point, button) => {
            if (!stack.list.length) return;
            if (button === Qt.RightButton) stack.go(stack.list[0]);
            else Island.toggle("agents", stack.bar.screenName, "pointer");
        }
    }
    Tip {
        shown: hover.hovered && !stack.open
        below: true
        text: !stack.list.length ? ""
            : (stack.many ? (stack.needN ? stack.needN + " need you · " : "") + Kittymux.working.length + " working"
                          : stack.list[0].agent + " · " + stack.list[0].title + " · " + stack.list[0].status)
              + "\nClick: every agent · right-click: go to " + (stack.many ? "the first" : "it")
    }
    function go(a) { if (!a) return; if (a.event) Kittymux.jumpEvent(a.event); else Kittymux.act(a.action); }
}
