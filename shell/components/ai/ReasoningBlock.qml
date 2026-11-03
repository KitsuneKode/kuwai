// The model's reasoning, as a quiet row like the tool rows. While it thinks,
// a highlight sweeps across "Thinking" and the newest lines show underneath;
// one second after it's done the block folds itself away and reads
// "Thought for 6s" (AI Elements reasoning.tsx: auto-open, AUTO_CLOSE 1000 ms).
// Click the row to open or close it.
import QtQuick
import QtQuick.Effects
import qs.config
import qs.components

Item {
    id: root

    property string text: ""
    property bool isThinking: false
    property real startedAt: 0
    property real endedAt: 0

    property bool expanded: isThinking
    onIsThinkingChanged: {
        if (isThinking) { expanded = true; closeTimer.stop(); }
        else closeTimer.restart();
    }
    Timer { id: closeTimer; interval: 1000; onTriggered: root.expanded = false }

    readonly property int seconds: startedAt > 0 && endedAt > startedAt ? Math.max(1, Math.round((endedAt - startedAt) / 1000)) : 0
    readonly property string label: isThinking ? "Thinking" : seconds > 0 ? "Thought for " + seconds + "s" : "Thought"

    implicitWidth: parent ? parent.width : 500
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 4

        Item {
            id: row
            width: parent.width
            height: 28

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Qt.rgba(1, 1, 1, area.containsMouse ? 0.05 : 0)
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
                    Icon { anchors.centerIn: parent; name: "brain"; size: 14; color: root.isThinking ? Theme.accent : Theme.textTertiary }
                }

                // The label, with a highlight sweeping through it while thinking.
                Item {
                    width: title.implicitWidth
                    height: title.implicitHeight
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        id: title
                        text: root.label
                        size: 13
                        color: root.isThinking ? Theme.textTertiary : Theme.textSecondary
                        layer.enabled: sweep.visible
                    }
                    Item {
                        id: sweepSource
                        anchors.fill: title
                        visible: false
                        layer.enabled: true
                        Rectangle {
                            width: 44
                            height: parent.height
                            x: -width + sweepX * (parent.width + width)
                            property real sweepX: 0
                            NumberAnimation on sweepX {
                                running: sweep.visible
                                from: 0; to: 1
                                duration: 1400
                                loops: Animation.Infinite
                            }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.5; color: Theme.textPrimary }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }
                    }
                    MultiEffect {
                        id: sweep
                        visible: root.isThinking && !Theme.reduceMotion
                        anchors.fill: title
                        source: sweepSource
                        maskEnabled: true
                        maskSource: title
                    }
                }

                Icon {
                    visible: root.text !== ""
                    opacity: area.containsMouse || root.expanded ? 1 : 0
                    name: "caret-right"
                    style: "bold"
                    size: 11
                    color: Theme.textTertiary
                    rotation: root.expanded ? 90 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
                    Behavior on rotation {
                        enabled: !Theme.reduceMotion
                        NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                    }
                }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.text !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: { closeTimer.stop(); root.expanded = !root.expanded; }
            }
        }

        // While thinking: the newest lines, pinned to the bottom. Done: all of it.
        Item {
            width: parent.width
            readonly property real full: body.implicitHeight
            height: root.expanded && root.text !== "" ? (root.isThinking ? Math.min(full, 110) : full) : 0
            visible: height > 0
            clip: true
            Behavior on height {
                enabled: !Theme.reduceMotion
                NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            }

            Text {
                id: body
                x: 30
                width: parent.width - 36
                y: Math.min(0, parent.height - implicitHeight)
                text: root.text.trim()
                color: Theme.textTertiary
                font.family: Theme.fontText
                font.pixelSize: 13
                lineHeight: 1.35
                wrapMode: Text.Wrap
            }
        }
    }
}
