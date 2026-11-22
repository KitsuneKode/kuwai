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
    property bool withT3: false
    readonly property var t3Rows: withT3 ? T3Code.items.filter(i => i.status === "waiting" || i.status === "running")
        .map(i => ({ agent: Agents.t3Agent(i.provider), title: i.title || "T3 thread", where: "T3", status: i.status === "waiting" ? "needs you" : "working",
                     needs: i.status === "waiting", thread: i.thread })) : []
    readonly property var waiting: Kittymux.attention.filter(e => e.severity === "needs-you")
        .map(e => ({ agent: e.agent, title: Kittymux.clean(e.tab || e.title), where: "", status: "needs you", needs: true, event: e.id }))
    // An agent kittymux reads as waiting (agents.json state) with no unread
    // event for its pane (it asked before the inbox caught it, or the event was
    // read): it's still asking, so it leads too. It was left out of the stack.
    readonly property var waitingPanes: Kittymux.running.filter(r => r.needs
        && !Kittymux.attention.some(e => e.severity === "needs-you" && String(e.pid) === String(r.pid) && String(e.w) === r.w))
    readonly property var list: waiting.concat(waitingPanes, t3Rows.filter(a => a.needs), Kittymux.working, t3Rows.filter(a => !a.needs))
    readonly property int needN: waiting.length + waitingPanes.length + t3Rows.filter(a => a.needs).length
    readonly property int workN: Kittymux.working.length + t3Rows.filter(a => !a.needs).length
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

    HoverHandler { id: hover; enabled: stack.enabled; margin: 6; cursorShape: Qt.PointingHandCursor }
    Accessible.role: Accessible.Button
    Accessible.name: !stack.list.length ? "" : stack.many ? "Agents: " + (stack.needN ? stack.needN + " need you, " : "") + stack.workN + " working"
        : stack.list[0].agent + ", " + stack.list[0].title + ", " + stack.list[0].status
    Accessible.description: "Opens every agent"
    Accessible.onPressAction: if (stack.list.length) Island.open("agents", stack.bar.screenName, "pointer")
    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (point, button) => {
            if (!stack.list.length) return;
            if (button === Qt.RightButton) stack.go(stack.list[0]);
            else Island.open("agents", stack.bar.screenName, "pointer");
        }
    }
    Tip {
        shown: hover.hovered && !stack.open
        below: true
        text: !stack.list.length ? ""
            : (stack.many ? (stack.needN ? stack.needN + " need you · " : "") + stack.workN + " working"
                          : stack.list[0].agent + " · " + stack.list[0].title + " · " + stack.list[0].status)
              + "\nClick: every agent · right-click: go to " + (stack.many ? "the first" : "it")
    }
    function go(a) { if (!a) return; if (a.thread) T3Code.openThread(a.thread); else if (a.event) Kittymux.jumpEvent(a.event); else Kittymux.act(a.action); }
}
