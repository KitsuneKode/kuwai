import QtQuick
import qs.components
import qs.config
import qs.services

Item {
    id: panel
    required property var sourceSplit
    readonly property var activities: sourceSplit.overflowSelection.filter(key => sourceSplit.demand[key])

    implicitWidth: Theme.panelS
    implicitHeight: rows.implicitHeight + 2 * Theme.s4
    Accessible.role: Accessible.Pane
    Accessible.name: heading.text

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: panel.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: rows
            x: Theme.s4
            y: Theme.s4
            width: parent.width - 2 * Theme.s4
            spacing: Theme.s2

            Label {
                id: heading
                text: "More activities"
                size: Theme.tHeadline
                weight: Theme.wSemibold
                width: parent.width
                wrapMode: Text.Wrap
            }
            Label {
                visible: panel.activities.length === 0
                text: "These activities have ended."
                width: parent.width
                wrapMode: Text.Wrap
                color: Theme.textSecondary
            }
            Repeater {
                model: panel.activities
                delegate: RaisedButton {
                    required property string modelData
                    objectName: "activity-" + modelData
                    text: panel.sourceSplit.labelFor(modelData)
                    kind: "secondary"
                    elideText: true
                    width: parent.width
                    height: Math.max(implicitHeight, panel.sourceSplit.minimumTarget)
                    onClicked: {
                        panel.sourceSplit.pillOf(modelData).activate();
                        if (modelData === "min") Island.close();
                    }
                }
            }
        }
    }
}
