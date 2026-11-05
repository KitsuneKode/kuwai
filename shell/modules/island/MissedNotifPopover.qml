// Notifications under the island bell (PopupWindow like TrayMenu — not clipped by the island body).
// Left-click → center; right-click / hold / Ctrl+click → quick list.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: pop
    property Item anchorItem
    property var window
    property bool open: false
    property bool anchorHovered: false
    property bool dismissOnAnchorLeave: true
    signal closed()
    // One list per change, and only while shown (not 4× per notification while closed).
    readonly property var quick: (open || k.value > 0.01) ? Notifs.bellQuickList(8) : []

    property bool counted: false
    onOpenChanged: {
        if (open && !counted && pop.window) { counted = true; pop.window.menus++; }
        else if (!open && counted && pop.window) { counted = false; pop.window.menus = Math.max(0, pop.window.menus - 1); }
        k.target = open ? 1 : 0;
    }
    Component.onDestruction: if (counted && window) window.menus = Math.max(0, window.menus - 1)

    width: 0
    height: 0

    QtObject {
        id: k
        property real target: 0
        property real value: 0
        Behavior on value { NumberAnimation { duration: k.target > 0 ? 200 : 120; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        onTargetChanged: value = target
    }

    function close() { closed(); }

    PopupWindow {
        id: popWin
        visible: pop.anchorItem && (pop.open || k.value > 0.01)
        color: "transparent"
        anchor.item: pop.anchorItem
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 10
        implicitWidth: 320
        implicitHeight: Math.min(420, card.implicitHeight + 16)

        Timer {
            interval: 650
            running: pop.open && pop.dismissOnAnchorLeave && !cardHover.hovered && !pop.anchorHovered
            onTriggered: pop.close()
        }
        HyprlandFocusGrab {
            // The popup itself must be in the grab, or the first click inside
            // it counts as "outside" and closes the list.
            windows: [popWin, ...(pop.window ? [pop.window] : [])]
            active: pop.open
            onCleared: pop.close()
        }

        Item {
            id: card
            x: 10; y: 4
            width: parent.implicitWidth - 20
            implicitHeight: header.height + list.contentHeight + footer.height + 24
            height: Math.min(400, implicitHeight)
            opacity: k.value
            scale: 0.96 + 0.04 * k.value
            transformOrigin: Item.Top
            HoverHandler { id: cardHover }

            GlassCard {
                anchors.fill: parent
                radius: 16
                tint: Theme.glassTintElevated
            }

            Column {
                id: header
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 2
                Label {
                    text: Notifs.missed.length ? "Need you"
                        : Notifs.unread ? (Notifs.inbox > 9 ? "Unread · 9+" : Notifs.inbox === 1 ? "Unread · 1" : "Unread · " + Notifs.inbox)
                        : "Recent"
                    size: 14; weight: Theme.wSemibold
                }
                Label {
                    visible: pop.quick.length > 0
                    text: Notifs.missed.length ? "Act on these first" : "Newest first · center for all"
                    size: 11; color: Theme.textTertiary
                }
            }

            Label {
                visible: pop.quick.length === 0
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 24
                text: "Nothing urgent right now"
                size: 12; color: Theme.textTertiary
            }

            ListView {
                id: list
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footer.top; margins: 8; topMargin: 6; bottomMargin: 4 }
                clip: true
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                visible: pop.quick.length > 0
                model: pop.quick

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool fresh: modelData.time > Notifs.lastSeen && !modelData.discard
                    readonly property bool hot: modelData.severity === "critical" || modelData.severity === "warning"
                    width: list.width
                    height: inner.implicitHeight + 20
                    radius: 14
                    color: hot ? Qt.alpha(modelData.severity === "critical" ? Theme.red : Theme.orange, 0.12)
                        : fresh ? Qt.alpha(Theme.accent, 0.1) : Qt.rgba(1, 1, 1, 0.06)
                    border.width: fresh || hot ? 1.5 : 1
                    border.color: modelData.severity === "critical" ? Qt.alpha(Theme.red, 0.45)
                        : modelData.severity === "warning" ? Qt.alpha(Theme.orange, 0.35)
                        : fresh ? Qt.alpha(Theme.accent, 0.4) : Qt.rgba(1, 1, 1, 0.08)

                    Column {
                        id: inner
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 4
                        Label {
                            width: parent.width
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: (modelData.app || "") + (modelData.title ? "  ·  " + modelData.title : "")
                            size: 12; weight: Theme.wSemibold
                        }
                        Item {
                            width: parent.width
                            height: Math.min(56, bodyFlick.contentHeight)
                            clip: true
                            Flickable {
                                id: bodyFlick
                                anchors.fill: parent
                                contentHeight: bodyLbl.implicitHeight
                                boundsBehavior: Flickable.StopAtBounds
                                Label {
                                    id: bodyLbl
                                    width: bodyFlick.width
                                    wrapMode: Text.Wrap
                                    text: Notifs.bodyForDisplay(modelData, true).replace(/<[^>]*>/g, "")
                                    size: 11; lineHeight: 1.35; color: Theme.textSecondary
                                }
                            }
                        }
                        Row {
                            spacing: 6
                            Rectangle {
                                height: 26; radius: 13
                                width: openL.implicitWidth + 20
                                color: openA.containsMouse ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(1, 1, 1, 0.88)
                                Label { id: openL; anchors.centerIn: parent; text: "Open"; size: 11; weight: Theme.wSemibold; color: "#111111" }
                                MouseArea {
                                    id: openA
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { pop.close(); Notifs.openInCenter(modelData, false, pop.window ? pop.window.screenName : ""); }
                                }
                            }
                            Rectangle {
                                visible: Notifs.canReply(modelData)
                                height: 26; radius: 13
                                width: repL.implicitWidth + 20
                                color: repA.containsMouse ? Theme.pillHover : Theme.pill
                                Label { id: repL; anchors.centerIn: parent; text: "Reply"; size: 11; weight: Theme.wMedium }
                                MouseArea {
                                    id: repA
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { pop.close(); Notifs.openInCenter(modelData, true, pop.window ? pop.window.screenName : ""); }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: footer
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                height: 36
                radius: 12
                color: allArea.containsMouse ? Theme.pillHover : Theme.pill
                Label { anchors.centerIn: parent; text: "Open notification center"; size: 12; weight: Theme.wSemibold }
                MouseArea {
                    id: allArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { pop.close(); Notifs.toggleCenter("notifications", "pointer", pop.window ? pop.window.screenName : ""); }
                }
            }
        }
    }
}
