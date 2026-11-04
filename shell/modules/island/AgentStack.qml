// Agents at work (kittymux), as their marks stacked one over the next, the
// first on top (three at most, then "+2"). Resting on it, the stack fans
// a little apart: there's more than one in there.
//
//   one     ✳                 click: the Agents tab · right-click: go to it
//   many    ✳◐◑ +2            click: the marks spring out into a chooser,
//                             one row each; pick one to go to its tab
//
//              ✳◐◑            ╭─────────────────────────────────╮
//               ╰──────────▶  │ ✳  claude   Fix the greeter  ~/r │
//                             │ ◐  codex    Write tests     ~/k │
//                             │ ◑  cursor   Refactor        ~/a │
//                             │ ⌁  All agents                    │
//                             ╰─────────────────────────────────╯
//
// Motion: one spring (critically damped, no overshoot) opens the card from
// its top right, under the stack; each mark travels from its place in the
// stack to its row, 40 ms after the one before, its words fading in behind
// it. Closing runs the same path back, quicker. Reduced motion: a fade.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.config
import qs.components
import qs.services

Item {
    id: stack
    property var bar
    readonly property var list: Kittymux.working
    readonly property int shown: Math.min(3, list.length)
    readonly property bool many: list.length > 1
    readonly property bool hovered: hover.hovered
    property bool open: false
    onManyChanged: if (!many) open = false

    property real step: hover.hovered && many && !open ? 10 : 8
    Behavior on step { enabled: !Theme.reduceMotion; NumberAnimation { duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
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
                visible: stack.many
                anchors.centerIn: parent
                width: parent.width + 4; height: width; radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.94)
            }
            Image {
                id: mark
                anchors.fill: parent
                sourceSize: Qt.size(26, 26)
                source: parent.a ? Kittymux.brand(parent.a.agent) : ""
                visible: status === Image.Ready
                opacity: stack.open ? 0.35 : 1
                Behavior on opacity { NumberAnimation { duration: 120 } }
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
            if (stack.many) {
                if (button === Qt.RightButton) { stack.open = false; Notifs.toggleCenter("agents", "pointer", stack.bar.screenName); }
                else stack.open = !stack.open;
            } else if (button === Qt.RightButton) Kittymux.act(stack.list[0].action);
            else Notifs.toggleCenter("agents", "pointer", stack.bar.screenName);
        }
    }
    Tip {
        shown: hover.hovered && !stack.open
        below: true
        text: !stack.list.length ? ""
            : stack.many ? stack.list.length + " agents working · click: choose one · right-click: all agents"
            : stack.list[0].agent + " · " + stack.list[0].title + " · working\nClick: all agents · right-click: go to it"
    }

    // Keep the island as it is while the chooser is open (IslandBar.menus).
    property bool counted: false
    onOpenChanged: {
        k.target = open ? 1 : 0;
        if (open && !counted) { counted = true; bar.menus++; }
        else if (!open && counted) { counted = false; bar.menus = Math.max(0, bar.menus - 1); }
    }
    Component.onDestruction: if (counted) bar.menus = Math.max(0, bar.menus - 1)
    Spring { id: k; tier: stack.open ? Theme.surfaceIn : Theme.surfaceOut; epsilon: 0.002 }
    function pick(a) { open = false; if (a) Kittymux.act(a.action); }

    PopupWindow {
        id: pop
        visible: stack.open || k.value > 0.01
        color: "transparent"
        anchor.item: stack
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        anchor.margins.top: 8
        implicitWidth: 340
        implicitHeight: card.height + 30

        Timer { interval: 700; running: stack.open && !cardHover.hovered && !hover.hovered; onTriggered: stack.open = false }
        HyprlandFocusGrab {
            windows: [pop, ...(stack.bar ? [stack.bar] : [])]
            active: stack.open
            onCleared: stack.open = false
        }

        readonly property real rowH: 40
        Item {
            id: card
            x: 12; y: 4
            width: pop.implicitWidth - 24
            height: rows.height + footer.height + 14
            readonly property real p: Math.max(0, Math.min(1, k.value))
            opacity: Math.min(1, card.p * 2)
            scale: Theme.reduceMotion ? 1 : 0.94 + 0.06 * card.p
            transformOrigin: Item.TopRight
            HoverHandler { id: cardHover }

            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    readonly property real s: 2 + index * 5
                    x: -s; y: -s + 6 + index * 2
                    width: card.width + s * 2; height: card.height + s * 2
                    radius: 16 + s
                    color: Qt.rgba(0, 0, 0, 0.09)
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: 16
                color: Qt.rgba(0.07, 0.07, 0.08, 0.97)
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.09)
            }

            Column {
                id: rows
                x: 6; y: 6
                width: card.width - 12
                Repeater {
                    model: stack.list
                    Item {
                        id: row
                        required property var modelData
                        required property int index
                        width: rows.width; height: pop.rowH
                        // 0 → 1, each 40 ms (≈0.12 of the spring) after the last.
                        readonly property real lag: Math.min(0.4, index * 0.12)
                        readonly property real t: Theme.reduceMotion ? card.p : Math.max(0, Math.min(1, (card.p - lag) / (1 - lag)))
                        // Where this mark sat in the stack, from the row's mark: the
                        // popup's top right is the stack's bottom right, 8 px down.
                        readonly property point from: Qt.point(
                            pop.implicitWidth - stack.width + Math.min(index, 2) * stack.step + stack.markSize / 2 - (card.x + rows.x + 20),
                            -(8 + stack.height / 2) - (card.y + rows.y + index * pop.rowH + pop.rowH / 2))
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: rowArea.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : "transparent"
                            Behavior on color { ColorAnimation { duration: 80 } }
                        }
                        Image {
                            id: rowMark
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            sourceSize: Qt.size(40, 40)
                            source: Kittymux.brand(row.modelData.agent)
                            transform: Translate {
                                x: Theme.reduceMotion ? 0 : row.from.x * (1 - row.t)
                                y: Theme.reduceMotion ? 0 : row.from.y * (1 - row.t)
                            }
                            scale: Theme.reduceMotion ? 1 : 0.65 + 0.35 * row.t
                            opacity: Math.min(1, row.t * 3)
                        }
                        Column {
                            anchors { left: rowMark.right; leftMargin: 10; right: where.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            opacity: Math.max(0, (row.t - 0.4) / 0.6)
                            spacing: 1
                            Label {
                                width: parent.width; elide: Text.ElideRight
                                text: row.modelData.title || row.modelData.agent
                                size: 13; weight: Theme.wMedium
                            }
                            Label {
                                width: parent.width; elide: Text.ElideRight
                                text: row.modelData.agent + (row.modelData.status ? " · " + row.modelData.status : "")
                                size: 11
                                color: Theme.textSecondary
                            }
                        }
                        Label {
                            id: where
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            width: Math.min(implicitWidth, 90); elide: Text.ElideLeft
                            opacity: Math.max(0, (row.t - 0.5) / 0.5)
                            text: row.modelData.where || ""
                            size: 11
                            color: Theme.textTertiary
                        }
                        MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: stack.pick(row.modelData) }
                    }
                }
            }
            Item {
                id: footer
                anchors { left: rows.left; right: rows.right; top: rows.bottom; topMargin: 2 }
                height: 32
                opacity: Math.max(0, (card.p - 0.5) / 0.5)
                Rectangle { x: 8; width: parent.width - 16; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
                Rectangle {
                    anchors { fill: parent; topMargin: 3 }
                    radius: 10
                    color: allArea.containsMouse ? Theme.pill : "transparent"
                }
                Label {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter; verticalCenterOffset: 1 }
                    text: "All agents…"
                    size: 12; weight: Theme.wMedium
                    color: Theme.textSecondary
                }
                MouseArea { id: allArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { stack.open = false; Notifs.toggleCenter("agents", "pointer", stack.bar.screenName); } }
            }
        }
    }
}
