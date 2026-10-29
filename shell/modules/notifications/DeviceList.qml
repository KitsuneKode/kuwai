import QtQuick
import Quickshell
import qs.config
import qs.components

// The Sound tab's device lists, pavucontrol's device pages, Control Center style: every device on
// one card; the default one ticked; each with its own volume and mute.
Column {
    id: devList
    required property var view
    property string title
    property string glyph
    property var nodes: []
    property var current: null
    signal picked(var node)
    width: parent ? parent.width : 0
    spacing: 8
    visible: nodes.length > 0

    Label { x: 4; text: devList.title; size: 14; weight: Theme.wSemibold; color: Theme.textSecondary }
    Rectangle {
        width: devList.width
        height: devices.implicitHeight + 8
        radius: 18
        color: Qt.rgba(1, 1, 1, 0.065)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.06)
        Column {
            id: devices
            x: 4; y: 4
            width: parent.width - 8
            Repeater {
                model: devList.nodes
                Item {
                    id: dev
                    required property var modelData
                    required property int index
                    readonly property bool on: devList.current === modelData
                    readonly property var audio: modelData.audio
                    width: devices.width
                    height: 64

                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: devHover.hovered && !dev.on ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                    }
                    Rectangle {
                        visible: dev.index > 0
                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 44; rightMargin: 10 }
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }
                    HoverHandler { id: devHover }

                    // Default: a filled disc with a tick; others a ring to click.
                    Rectangle {
                        id: pick
                        x: 12; y: 12
                        width: 22; height: 22; radius: 11
                        color: dev.on ? Theme.blue : "transparent"
                        border.width: dev.on ? 0 : 1.5
                        border.color: pickArea.containsMouse ? Theme.textSecondary : Theme.textTertiary
                        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                        Text {
                            anchors.centerIn: parent
                            visible: dev.on
                            text: "\u{f012c}"
                            font.family: Theme.fontGlyph
                            font.pixelSize: 14
                            color: "white"
                        }
                    }
                    Label {
                        anchors { left: pick.right; leftMargin: 10; right: muteBtn.left; rightMargin: 8; verticalCenter: pick.verticalCenter }
                        elide: Text.ElideRight
                        text: devList.view.center.highlight(devList.view.deviceName(dev.modelData))
                        textFormat: Text.StyledText
                        size: 13
                        weight: dev.on ? Theme.wSemibold : Theme.wMedium
                        color: dev.on ? Theme.textPrimary : Theme.textSecondary
                    }
                    MouseArea {
                        id: pickArea
                        anchors { left: parent.left; right: muteBtn.left; top: parent.top }
                        height: 34
                        hoverEnabled: true
                        cursorShape: dev.on ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: if (!dev.on) devList.picked(dev.modelData)
                    }
                    Rectangle {
                        id: muteBtn
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: pick.verticalCenter }
                        width: 26; height: 22; radius: 11
                        readonly property bool muted: dev.audio ? dev.audio.muted : false
                        color: muted ? Qt.alpha(Theme.red, 0.85) : muteDevArea.containsMouse ? Theme.pillHover : Theme.pill
                        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                        Text {
                            anchors.centerIn: parent
                            text: muteBtn.muted ? "\u{f075f}" : "\u{f057e}"
                            font.family: Theme.fontGlyph
                            font.pixelSize: 13
                            color: muteBtn.muted ? "white" : Theme.textSecondary
                        }
                        MouseArea {
                            id: muteDevArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (dev.audio) dev.audio.muted = !dev.audio.muted
                        }
                    }
                    Slider {
                        anchors { left: pick.right; leftMargin: 10; right: parent.right; rightMargin: 10; bottom: parent.bottom; bottomMargin: 6 }
                        height: 22
                        value: dev.audio ? dev.audio.volume : 0
                        dim: muteBtn.muted
                        fillColor: dev.on ? Qt.alpha(Theme.blue, 0.55) : Qt.rgba(1, 1, 1, 0.18)
                        onMoved: v => { if (dev.audio) dev.audio.volume = v; }
                        onRightClicked: if (dev.audio) dev.audio.muted = !dev.audio.muted
                    }
                }
            }
        }
    }
}

