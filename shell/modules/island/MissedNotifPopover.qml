// Missed notifications under the island bell: scrollable preview cards with
// Open / Reply instead of a flat tray menu.
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
    signal closed()
    property bool counted: false
    onOpenChanged: {
        if (open && !counted && pop.window) { counted = true; pop.window.menus++; }
        else if (!open && counted && pop.window) { counted = false; pop.window.menus = Math.max(0, pop.window.menus - 1); }
        if (!open) { closed(); k.target = 0; } else k.target = 1;
    }
    Component.onDestruction: if (counted && window) window.menus = Math.max(0, window.menus - 1)

    width: 0; height: 0

    QtObject {
        id: k
        property real target: 0
        property real value: 0
        Behavior on value { NumberAnimation { duration: k.target > 0 ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        onTargetChanged: value = target
    }

    function close() { open = false; }

    PopupWindow {
        visible: pop.anchorItem && (pop.open || k.value > 0.01)
        color: "transparent"
        anchor.item: pop.anchorItem
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 10
        implicitWidth: 320
        implicitHeight: Math.min(420, card.implicitHeight + 20)

        Timer {
            interval: 650
            running: pop.open && !cardHover.hovered && !pop.anchorHovered
            onTriggered: pop.close()
        }
        HyprlandFocusGrab {
            windows: [parent, ...(pop.window ? [pop.window] : [])]
            active: pop.open
            onCleared: pop.close()
        }

        Item {
            id: card
            x: 10; y: 6
            width: parent.implicitWidth - 20
            implicitHeight: header.height + list.contentHeight + 14
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
                Label { text: "Missed"; size: 14; weight: Theme.wSemibold }
                Label {
                    text: Notifs.missed.length + " to look at · scroll for more"
                    size: 11; color: Theme.textTertiary
                }
            }

            ListView {
                id: list
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; margins: 8; topMargin: 6 }
                clip: true
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                model: Notifs.missed.slice(0, 6)

                delegate: Rectangle {
                    required property var modelData
                    width: list.width
                    height: inner.implicitHeight + 20
                    radius: 14
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: modelData.severity === "critical" ? Qt.alpha(Theme.red, 0.35)
                        : modelData.severity === "warning" ? Qt.alpha(Theme.orange, 0.28) : Qt.rgba(1, 1, 1, 0.08)

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
                                    text: String(modelData.body || "").replace(/<[^>]*>/g, "")
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
        }
    }
}
