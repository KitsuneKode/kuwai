import QtQuick
import qs.config
import qs.components
import qs.components.ui as Ui

Rectangle {
    id: root

    property var request: ({})
    signal decided(string decision)

    readonly property string kind: request.kind || "command"
    readonly property string verb: kind === "command" ? "Run" : kind === "write" ? "Save" : "Open"

    implicitHeight: col.implicitHeight + 24
    radius: Theme.r3
    color: Theme.wash(1)
    border.width: 1
    border.color: Theme.edge(1)

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
                name: root.kind === "command" ? "terminal-window" : root.kind === "launch" ? "app-window"
                    : root.kind === "write" ? "file-text" : "link"
                size: 15
                color: Theme.accent
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                text: root.kind === "command" ? "Run this command?"
                    : root.kind === "write" ? (root.request.summary || "Change a file") + "?"
                    : root.kind === "launch" ? (root.request.summary || "Open an app") + "?"
                    : "Open this link?"
                size: Theme.tBody
                weight: Theme.wSemibold
                color: Theme.textPrimary
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle {
            visible: root.kind !== "launch"
            width: parent.width
            implicitHeight: detail.implicitHeight + 16
            radius: Theme.innerRadius(root.radius, 4)
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
                text: root.kind === "write" ? "Only this file changes." : "It runs as you, in your home folder."
                visible: root.kind === "command" || root.kind === "write"
                size: Theme.tSub
                color: Theme.textTertiary
                anchors.left: parent.left
                anchors.right: btnRow.left
                anchors.rightMargin: 12
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }

            Row {
                id: btnRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Ui.Button {
                    kind: "secondary"
                    text: "Don't " + root.verb.toLowerCase()
                    onClicked: root.decided("decline")
                }
                Ui.Button {
                    kind: "primary"
                    text: root.verb
                    onClicked: root.decided("accept")
                }
            }
        }

        Row {
            anchors.right: parent.right
            spacing: 4
            KeyCap { text: "Esc"; size: Theme.tCaption }
            Label { text: "don't"; size: Theme.tFootnote; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
            Item { width: 8; height: 1 }
            KeyCap { text: "⌃"; size: Theme.tCaption }
            KeyCap { text: "↵"; size: Theme.tCaption }
            Label { text: root.verb.toLowerCase(); size: Theme.tFootnote; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
