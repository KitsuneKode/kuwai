import QtQuick
import qs.config
import qs.components

Rectangle {
    id: root

    property var request: ({})
    signal answered(string text)
    signal skipped()

    readonly property var options: request.options || []
    property Item hoverRow: null

    implicitHeight: col.implicitHeight + 24
    radius: Theme.r2
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
            width: parent.width
            spacing: 8
            Icon {
                id: qIcon
                name: "question"
                size: 15
                color: Theme.accent
                y: 1
            }
            Label {
                width: parent.width - qIcon.width - 8
                text: root.request.summary || ""
                size: Theme.tBody
                weight: Theme.wSemibold
                color: Theme.textPrimary
                wrapMode: Text.Wrap
            }
        }

        Item {
            visible: root.options.length > 0
            width: parent.width
            height: opts.implicitHeight

            FluidHighlight {
                target: root.hoverRow
                radius: Theme.r1
            }

            Column {
                id: opts
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.options
                    delegate: Item {
                        id: opt
                        required property string modelData
                        required property int index
                        width: opts.width
                        height: Math.max(34, optLabel.implicitHeight + 14)

                        KeyCap {
                            id: key
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(opt.index + 1)
                            size: Theme.tCaption
                        }
                        Label {
                            id: optLabel
                            anchors { left: key.right; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            text: opt.modelData
                            size: Theme.tBody
                            color: optArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                            wrapMode: Text.Wrap
                            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                        }
                        MouseArea {
                            id: optArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: {
                                if (containsMouse) root.hoverRow = opt;
                                else if (root.hoverRow === opt) root.hoverRow = null;
                            }
                            onClicked: root.answered(opt.modelData)
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: opt.modelData
                        Accessible.description: "Key " + (opt.index + 1)
                        Accessible.onPressAction: root.answered(opt.modelData)
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 18
            Label {
                text: root.options.length ? "Or type your own answer below" : "Type your answer below"
                size: Theme.tSub
                color: Theme.textTertiary
                anchors.verticalCenter: parent.verticalCenter
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                KeyCap { text: "↵"; size: Theme.tCaption }
                Label { text: "answer"; size: Theme.tFootnote; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 8; height: 1 }
                KeyCap { text: "Esc"; size: Theme.tCaption }
                Label {
                    text: "skip"
                    size: Theme.tFootnote
                    color: Theme.textTertiary
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.skipped() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Skip the question"
                    Accessible.onPressAction: root.skipped()
                }
            }
        }
    }
}
