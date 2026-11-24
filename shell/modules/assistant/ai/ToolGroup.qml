import QtQuick
import qs.config
import qs.components
import "../../../services/ai/turn.mjs" as Turn

Item {
    id: root

    property var parts: []
    property bool live: false
    property bool userOpen: false

    readonly property bool anyPending: parts.some(p => p.request && p.request.state === "pending")
    readonly property bool anyFailed: parts.some(p => p.status === "failed")
    readonly property bool folds: parts.length > 1
    readonly property bool open: !folds || live || anyPending || userOpen

    implicitWidth: parent ? parent.width : 500
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 2

        Item {
            visible: root.folds && !root.live && !root.anyPending
            width: parent.width
            height: 28

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Qt.rgba(1, 1, 1, sumArea.containsMouse ? 0.05 : 0)
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            }
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Item {
                    width: 16; height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    Icon { anchors.centerIn: parent; name: "wrench"; size: 14; color: Theme.textTertiary }
                }
                Label {
                    text: (Turn.toolSummary(root.parts) || ("Used " + root.parts.length + " tools")) + (root.anyFailed ? " · one failed" : "")
                    size: 13
                    color: Theme.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }
                Icon {
                    name: "caret-right"
                    style: "bold"
                    size: 11
                    color: Theme.textTertiary
                    rotation: root.userOpen ? 90 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on rotation {
                        enabled: !Theme.reduceMotion
                        NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                    }
                }
            }
            MouseArea {
                id: sumArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.userOpen = !root.userOpen
            }
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: (Turn.toolSummary(root.parts) || ("Used " + root.parts.length + " tools")) + (root.anyFailed ? ", one failed" : "")
            Accessible.expandable: true
            Accessible.expanded: root.userOpen
            Accessible.onPressAction: root.userOpen = !root.userOpen
            Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.userOpen = !root.userOpen; e.accepted = true; } }
            FocusRing { cornerRadius: Theme.r1 }
        }

        Item {
            width: parent.width
            height: root.open ? rows.implicitHeight : 0
            visible: height > 0
            clip: true
            Behavior on height {
                enabled: !Theme.reduceMotion && root.folds
                NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            }

            Column {
                id: rows
                width: parent.width
                x: root.folds && !root.live ? 10 : 0
                spacing: 2

                Repeater {
                    model: root.parts.length
                    Tool {
                        width: rows.width - rows.x
                        part: root.parts[index] || ({})
                    }
                }
            }
        }
    }
}
