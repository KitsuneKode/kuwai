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
    property bool withDesktop: true
    property string only: ""
    readonly property var all: Agents.stack("").filter(a => (withT3 || a.src !== "t3") && (withDesktop || a.src !== "desktop"))
        .map(a => Object.assign({}, a, { title: a.title || (a.src === "t3" ? "T3 thread" : Kittymux.agentLabel(a.agent)), desktop: a.hook }))
    readonly property var list: only === "needs" ? all.filter(a => a.needs) : only === "work" ? all.filter(a => !a.needs) : all
    readonly property var t3Rows: all.filter(a => a.src === "t3")
    readonly property var tuiRows: all.filter(a => a.src === "kitty")
    readonly property var desktopRows: all.filter(a => a.src === "desktop")
    readonly property var marks: Agents.stackMarks(list, 3)
    readonly property int needN: list.filter(a => a.needs).length
    readonly property int workN: list.length - needN
    readonly property int shown: Math.min(3, list.length)
    readonly property bool many: list.length > 1
    readonly property bool hovered: hover.hovered
    // Kept for IslandRest's marksHovered: the panel now answers in the island itself.
    readonly property bool open: Island.panel === "agents"

    property real step: hover.hovered && many && !open ? 10 : 8
    Behavior on step { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.microMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    readonly property int markSize: 13
    implicitWidth: marksRow.implicitWidth
    implicitHeight: 16

    Row {
        id: marksRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: stack.step - 2
        Repeater {
            model: stack.marks.marks
            Row {
                id: m
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: stack.markSize + 4; height: width
                    Rectangle {
                        visible: m.modelData.needs
                        anchors.fill: parent; radius: width / 2
                        color: "transparent"
                        border.width: 1.5; border.color: Theme.orange
                    }
                    Image {
                        id: markImg
                        anchors.centerIn: parent
                        width: stack.markSize; height: width
                        sourceSize: Qt.size(26, 26)
                        source: Kittymux.brand(m.modelData.agent)
                        visible: status === Image.Ready
                        opacity: stack.open ? 0.35 : 1
                        Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
                    }
                    Text {
                        visible: !markImg.visible
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "\u{f06a9}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.tBody
                        color: Theme.textSecondary
                    }
                }
                Label {
                    visible: m.modelData.count > 1
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 1
                    text: String(m.modelData.count)
                    size: Theme.tCaption; weight: Theme.wBold; rounded: true
                    color: m.modelData.needs ? Theme.orange : Theme.textSecondary
                    tabular: true
                }
            }
        }
        Label {
            visible: stack.marks.more > 0
            anchors.verticalCenter: parent.verticalCenter
            text: "+" + stack.marks.more
            size: Theme.tFootnote; weight: Theme.wSemibold; rounded: true
            color: Theme.textSecondary
        }
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
            : (stack.many ? [stack.t3Rows.length ? "T3 " + stack.t3Rows.length : "",
                             stack.tuiRows.length ? "TUI " + stack.tuiRows.length : "",
                             stack.desktopRows.length ? "Desktop " + stack.desktopRows.length : ""].filter(x => x).join(" · ")
                             + " (" + (stack.needN ? stack.needN + " need you · " : "") + stack.workN + " working)"
                          : (stack.list[0].where ? stack.list[0].where + " · " : "") + Kittymux.agentLabel(stack.list[0].agent) + " · " + stack.list[0].title + " · " + stack.list[0].status)
              + "\nClick: every agent · right-click: go to " + (stack.many ? "the first" : "it")
    }
    function go(a) {
        if (!a) return;
        if (a.thread) T3Code.openThread(a.thread);
        else if (a.src === "desktop") Agents.focusDesktop(a);
        else if (a.event) Kittymux.jumpEvent(a.event);
        else Kittymux.act(a.action);
    }
}
