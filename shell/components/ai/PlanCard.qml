// The agent's plan for a task (its update_plan tool; AI Elements Plan / Task,
// Codex's checklist): one card that updates in place as steps start and
// finish. Done steps dim and strike through, the current one is bright with a
// spinner, the rest wait as hollow circles. "2 of 5" in the header.
import QtQuick
import qs.config
import qs.components

Rectangle {
    id: root
    property var steps: []
    property bool live: false
    readonly property int done: steps.filter(s => s.status === "completed").length

    implicitHeight: col.implicitHeight + 22
    radius: 12
    color: Qt.rgba(1, 1, 1, 0.035)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; topMargin: 11 }
        spacing: 8

        Item {
            width: parent.width
            height: 18
            Row {
                spacing: 7
                anchors.verticalCenter: parent.verticalCenter
                Icon { name: "list-checks"; size: 14; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
                Label { text: "Plan"; size: 12; weight: Theme.wSemibold; color: Theme.textSecondary; anchors.verticalCenter: parent.verticalCenter }
            }
            Label {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.done + " of " + root.steps.length
                size: 11
                color: Theme.textTertiary
                font.features: { "tnum": 1 }
            }
        }

        Repeater {
            model: root.steps.length
            Row {
                id: stepRow
                required property int index
                readonly property var step: root.steps[index] || ({})
                readonly property bool isDone: step.status === "completed"
                readonly property bool isNow: step.status === "in_progress"
                width: col.width
                spacing: 9

                Item {
                    width: 16; height: 18
                    Icon {
                        anchors.centerIn: parent
                        name: stepRow.isDone ? "check-circle" : stepRow.isNow ? "circle-notch" : "circle"
                        style: stepRow.isDone ? "fill" : stepRow.isNow ? "bold" : "regular"
                        size: 15
                        color: stepRow.isDone ? Theme.green : stepRow.isNow ? Theme.accent : Theme.textDim
                        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                        RotationAnimation on rotation {
                            running: stepRow.isNow && root.live && !Theme.reduceMotion
                            loops: Animation.Infinite; from: 0; to: 360; duration: 1100
                        }
                        onNameChanged: rotation = 0
                    }
                }
                Label {
                    width: stepRow.width - 25
                    text: stepRow.step.step || ""
                    size: 13
                    wrapMode: Text.Wrap
                    weight: stepRow.isNow ? Theme.wMedium : Theme.wRegular
                    color: stepRow.isDone ? Theme.textTertiary : stepRow.isNow ? Theme.textPrimary : Theme.textSecondary
                    font.strikeout: stepRow.isDone
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                }
            }
        }
    }
}
