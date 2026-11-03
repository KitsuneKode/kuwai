// The agent wants to act on the machine: show exactly what it will do and
// wait. Lives under its tool row; once answered the row says what happened.
// Keys (handled by the overlay): ⌃↵ allow, Esc don't.
// Refs: AI Elements confirmation.tsx, T3 Code TimelinePendingApprovalRow,
// Codex bottom_pane/approval_overlay.rs.
import QtQuick
import qs.config
import qs.components

Rectangle {
    id: root

    // { id, kind: "command"|"launch"|"open_url", summary, detail, state }
    property var request: ({})
    signal decided(string decision)

    readonly property string kind: request.kind || "command"
    readonly property string verb: kind === "command" ? "Run" : "Open"

    implicitHeight: col.implicitHeight + 24
    radius: 12
    color: Qt.rgba(1, 1, 1, 0.05)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.10)

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        Row {
            spacing: 8
            Icon {
                name: root.kind === "command" ? "terminal-window" : root.kind === "launch" ? "app-window" : "link"
                size: 15
                color: Theme.accent
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                text: root.kind === "command" ? "Run this command?"
                    : root.kind === "launch" ? (root.request.summary || "Open an app") + "?"
                    : "Open this link?"
                size: 13
                weight: Theme.wSemibold
                color: Theme.textPrimary
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // What will run, exactly as it will run.
        Rectangle {
            visible: root.kind !== "launch"
            width: parent.width
            implicitHeight: detail.implicitHeight + 16
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.30)

            TextEdit {
                id: detail
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                text: root.request.detail || ""
                readOnly: true
                selectByMouse: true
                selectionColor: Qt.alpha(Theme.accent, 0.5)
                wrapMode: TextEdit.WrapAnywhere
                color: Theme.textPrimary
                font.family: Theme.fontMono
                font.pixelSize: 12
            }
        }

        Item {
            width: parent.width
            height: 34

            Label {
                text: "It runs as you, in your home folder."
                visible: root.kind === "command"
                size: 12
                color: Theme.textTertiary
                anchors.verticalCenter: parent.verticalCenter
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                RaisedButton {
                    kind: "secondary"
                    text: "Don't " + root.verb.toLowerCase()
                    onClicked: root.decided("decline")
                }
                RaisedButton {
                    kind: "primary"
                    text: root.verb
                    onClicked: root.decided("accept")
                }
            }
        }

        Row {
            anchors.right: parent.right
            spacing: 4
            KeyCap { text: "Esc"; size: 9 }
            Label { text: "don't"; size: 11; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
            Item { width: 8; height: 1 }
            KeyCap { text: "⌃"; size: 9 }
            KeyCap { text: "↵"; size: 9 }
            Label { text: root.verb.toLowerCase(); size: 11; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
