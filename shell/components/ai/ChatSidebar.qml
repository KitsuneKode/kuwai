// Port of shadcn AI Elements: <ChatSidebar>
// Collapsible sidebar showing conversation threads, new chat button, and model details.
// Features Fluid Functionalism's gliding highlight across thread items and honest status reporting.
import QtQuick
import QtQuick.Controls
import qs.config
import qs.components
import qs.services

Rectangle {
    id: root

    property bool open: true
    signal newChatRequested()
    signal sessionSelected(string id)

    implicitWidth: open ? 270 : 0
    implicitHeight: parent ? parent.height : 600
    clip: true
    color: Qt.rgba(0.04, 0.04, 0.05, 0.65)
    border.width: open ? 1 : 0
    border.color: Qt.rgba(1, 1, 1, 0.06)

    // Opens in 240 ms, closes quicker (180); both ease out (an ease-in close lags).
    Behavior on implicitWidth {
        enabled: !Theme.reduceMotion
        NumberAnimation {
            duration: root.open ? 240 : 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.easeOut
        }
    }

    Item {
        width: 270
        height: parent.height
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: root.open ? 180 : 120; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // ── Sidebar Header: "Chats" & "New Chat" Button ──────────
            Item {
                width: parent.width
                height: 36

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Icon {
                        name: "chats"
                        size: 16
                        color: Theme.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Label {
                        text: "Threads"
                        size: 14
                        weight: Theme.wSemibold
                        color: Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        height: 18
                        width: countLabel.implicitWidth + 10
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.08)
                        anchors.verticalCenter: parent.verticalCenter

                        Label {
                            id: countLabel
                            anchors.centerIn: parent
                            text: OllamaService.sessions.length
                            size: 11
                            color: Theme.textTertiary
                        }
                    }
                }

                // New Chat Button
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 30
                    width: newRow.implicitWidth + 14
                    radius: 8
                    color: newArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    Row {
                        id: newRow
                        anchors.centerIn: parent
                        spacing: 5

                        Icon {
                            name: "plus"
                            size: 12
                            color: Theme.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Label {
                            text: "New"
                            size: 12
                            weight: Theme.wMedium
                            color: Theme.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Row {
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter
                            KeyCap { text: "Ctrl"; size: 9 }
                            KeyCap { text: "N"; size: 9 }
                        }
                    }

                    MouseArea {
                        id: newArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            OllamaService.newChat();
                            root.newChatRequested();
                        }
                    }
                }
            }

            // ── Hairline Divider ──────────────────────────────────────
            Rectangle {
                width: parent.width
                height: 1
                color: Qt.rgba(1, 1, 1, 0.06)
            }

            // ── Sessions List (with FluidHighlight) ───────────────────
            // Hairline divider on right edge
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Qt.rgba(1, 1, 1, 0.08)
        visible: root.open
    }

    Item {
                width: parent.width
                height: Math.max(100, parent.height - 36 - 1 - 42 - 30)
                clip: true

                ListView {
                    id: sessionList
                    anchors.fill: parent
                    model: OllamaService.sessions
                    spacing: 6
                    clip: true

                    // Gliding FluidHighlight
                    FluidHighlight {
                        target: sessionList.currentItem
                        radius: 8
                    }

                    delegate: Item {
                        id: rowItem
                        width: sessionList.width
                        height: 44

                        readonly property bool isSelected: modelData.id === OllamaService.activeSessionId
                        readonly property bool isHovered: rowArea.containsMouse

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: rowItem.isSelected ? Qt.alpha(Theme.accent, 0.12) : "transparent"
                            border.width: rowItem.isSelected ? 1 : 0
                            border.color: Qt.alpha(Theme.accent, 0.25)
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: delBtn.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Icon {
                                name: "chat-circle"
                                size: 14
                                color: rowItem.isSelected ? Theme.accent : Theme.textTertiary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                width: parent.width - 26

                                Label {
                                    text: modelData.title || "New Chat"
                                    size: 13
                                    weight: rowItem.isSelected ? Theme.wSemibold : Theme.wRegular
                                    color: rowItem.isSelected ? Theme.textPrimary : Theme.textSecondary
                                    elide: Text.ElideRight
                                    width: parent.width
                                }

                                Label {
                                    text: OllamaService.formatRelative(modelData.updatedAt)
                                    size: 11
                                    color: Theme.textDim
                                }
                            }
                        }

                        // Delete Session Button (reveals on hover)
                        Rectangle {
                            id: delBtn
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22; height: 22
                            radius: 5
                            visible: rowItem.isHovered || delArea.containsMouse
                            color: delArea.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"

                            Icon {
                                anchors.centerIn: parent
                                name: "trash"
                                size: 12
                                color: delArea.containsMouse ? Theme.red : Theme.textTertiary
                            }

                            MouseArea {
                                id: delArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: OllamaService.deleteSession(modelData.id)
                            }
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            anchors.rightMargin: 28
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                OllamaService.switchSession(modelData.id);
                                root.sessionSelected(modelData.id);
                            }
                        }
                    }
                }
            }

            // ── Footer: Honest Daemon Status Chip ─────────────────────
            Rectangle {
                width: parent.width
                height: 42
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Rectangle {
                        width: 7; height: 7
                        radius: 3.5
                        color: OllamaService.status === "ready" ? Theme.green
                             : OllamaService.status === "loading" ? Theme.yellow
                             : Theme.red
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Icon {
                        name: "cpu"
                        size: 13
                        color: Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Label {
                        text: OllamaService.status === "ready"
                            ? (OllamaService.model + " • Ready")
                            : "Ollama Offline"
                        size: 12
                        weight: Theme.wMedium
                        color: OllamaService.status === "ready" ? Theme.textSecondary : Theme.red
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
