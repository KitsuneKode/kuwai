// Port of shadcn AI Elements: <Context>
// A slim progress bar showing how full the conversation's context window is.
// Color shifts from accent → orange → red as usage grows.
import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root
    implicitHeight: 20
    implicitWidth: parent ? parent.width : 200

    visible: OllamaService.contextUsed > 0

    readonly property real ratio: OllamaService.contextTotal > 0
        ? Math.min(1, OllamaService.contextUsed / OllamaService.contextTotal)
        : 0
    readonly property color barColor: ratio > 0.85 ? Theme.red
        : ratio > 0.65 ? Theme.orange
        : Theme.accent

    Row {
        anchors.fill: parent
        spacing: 8

        Icon {
            name: "database"
            size: 12
            color: Theme.textDim
            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            width: parent.width - ctxLabel.implicitWidth - 28
            height: 4
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.06)
            }

            Rectangle {
                height: parent.height
                width: parent.width * root.ratio
                radius: 2
                color: root.barColor
                Behavior on width {
                    NumberAnimation {
                        duration: Theme.glideMs
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.easeOut
                    }
                }
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            }
        }

        Label {
            id: ctxLabel
            text: OllamaService.contextUsed + " / " + OllamaService.contextTotal + " ctx"
            size: 11
            color: Theme.textDim
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
