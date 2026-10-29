// Every shortcut, one sheet: press ? (or ⌃/) in the center. It rises from
// the bottom of the panel on the moderate spring and drops back on a quick
// ease-out; Esc, ? or a click outside it closes it.
import QtQuick
import qs.config
import qs.components

Item {
    id: sheet

    property bool open: false
    readonly property real p: rise.value
    visible: p > 0.001

    Spring { id: rise; tier: Theme.springModerate; target: sheet.open ? 1 : 0; epsilon: 0.001 }

    readonly property var groups: [
        { title: "Navigate", rows: [
            { keys: ["↑", "↓"], label: "Select" },
            { keys: ["→", "←"], label: "Expand or fold a group" },
            { keys: ["⇥"], label: "Next filter" },
            { keys: ["⌃", "⇥"], label: "Switch tab" },
            { keys: ["⌥", "1"], label: "Notifications" },
            { keys: ["⌥", "2"], label: "Agents" } ] },
        { title: "Act", rows: [
            { keys: ["↩"], label: "Open" },
            { keys: ["⌫"], label: "Dismiss (when search is empty)" },
            { keys: ["⌃", "⇧", "⌫"], label: "Clear all · mark all read" },
            { keys: ["⌃", "D"], label: "Do Not Disturb" } ] },
        { title: "Search", rows: [
            { keys: ["Type"], label: "Search everything" },
            { keys: ["⎋"], label: "Clear search, then close" } ] },
        { title: "Anywhere", rows: [
            { keys: ["Super", "N"], label: "Notifications" },
            { keys: ["Super", "⇧", "N"], label: "Agents" },
            { keys: ["Super", "⌥", "N"], label: "Do Not Disturb" },
            { keys: ["Super", "⇧", "⌥", "N"], label: "Open the newest notification" } ] }
    ]

    // Dim what's behind, so the sheet is the one thing in focus.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35 * sheet.p)
        MouseArea { anchors.fill: parent; enabled: sheet.open; onClicked: sheet.open = false }
    }

    Rectangle {
        id: card
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
        // Never taller than the panel; scrolls when it has to.
        height: Math.min(body.implicitHeight + 32, sheet.height - 16)
        radius: 18
        color: Qt.rgba(0.11, 0.11, 0.13, 0.97)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
        transform: Translate { y: Theme.reduceMotion ? 0 : (1 - sheet.p) * (card.height * 0.35) }
        opacity: Math.min(1, sheet.p * 1.4)
        MouseArea { anchors.fill: parent }          // clicks on the sheet stay on it

        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            clip: true
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

        Column {
            id: body
            width: parent.width
            spacing: 14

            Item {
                width: parent.width
                height: 20
                Label { text: "Keyboard shortcuts"; size: 15; weight: Theme.wSemibold }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    KeyCap { text: "?" }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: " close"; size: 12; color: Theme.textTertiary }
                }
            }

            Repeater {
                model: sheet.groups
                Column {
                    id: group
                    required property var modelData
                    width: body.width
                    spacing: 6
                    Label { text: group.modelData.title; size: 12; weight: Theme.wSemibold; color: Theme.textTertiary }
                    Repeater {
                        model: group.modelData.rows
                        Item {
                            id: line
                            required property var modelData
                            width: body.width
                            height: 22
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: line.modelData.label
                                size: 13
                                color: Theme.textSecondary
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                Repeater {
                                    model: line.modelData.keys
                                    KeyCap { required property string modelData; text: modelData }
                                }
                            }
                        }
                    }
                }
            }
        }
        }
    }
}
