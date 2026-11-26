import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
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
    property Item hoverRow: null
    width: parent ? parent.width : 0
    spacing: 8
    visible: nodes.length > 0

    Label { x: 4; text: devList.title; size: Theme.tCallout; weight: Theme.wSemibold; color: Theme.textSecondary }
    Rectangle {
        width: devList.width
        height: devices.implicitHeight + 8
        radius: 18
        color: Theme.wash(1)
        border.width: 1
        border.color: Theme.edge(0)
        FluidHighlight { target: devList.hoverRow; radius: 14 }
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
                        visible: dev.index > 0
                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 44; rightMargin: 10 }
                        height: 1
                        color: Theme.wash(1)
                    }
                    HoverHandler {
                        id: devHover
                        onHoveredChanged: {
                            if (hovered && !dev.on) devList.hoverRow = dev;
                            else if (devList.hoverRow === dev) devList.hoverRow = null;
                        }
                    }
                    onOnChanged: if (on && devList.hoverRow === dev) devList.hoverRow = null

                    // Default: a filled disc with a tick; others a ring to click.
                    Rectangle {
                        id: pick
                        x: 12; y: 12
                        width: 22; height: 22; radius: 11
                        color: dev.on ? Theme.accent : "transparent"
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
                        size: Theme.tBody
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
                        activeFocusOnTab: true
                        Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (!dev.on) devList.picked(dev.modelData); e.accepted = true; } }
                        FocusRing { cornerRadius: Theme.r2 }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: devList.view.deviceName(dev.modelData)
                        Accessible.checkable: true
                        Accessible.checked: dev.on
                        Accessible.onPressAction: if (!dev.on) devList.picked(dev.modelData)
                    }
                    Rectangle {
                        id: muteBtn
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: pick.verticalCenter }
                        width: 26; height: 22; radius: 11
                        readonly property bool muted: dev.audio ? dev.audio.muted : false
                        color: muted ? Qt.alpha(Theme.red, 0.85) : muteDevArea.containsMouse ? Theme.pillHover : Theme.pill
                        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                        Text {
                            textFormat: Text.PlainText
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
                        activeFocusOnTab: !!dev.audio
                        Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (dev.audio) dev.audio.muted = !dev.audio.muted; e.accepted = true; } }
                        FocusRing {}
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: "Mute " + devList.view.deviceName(dev.modelData)
                        Accessible.checkable: true
                        Accessible.checked: muteBtn.muted
                        Accessible.onPressAction: if (dev.audio) dev.audio.muted = !dev.audio.muted
                        Accessible.onToggleAction: if (dev.audio) dev.audio.muted = !dev.audio.muted
                    }
                    // Live level, pavucontrol-style: one slim bar per channel under the
                    // slider (green, yellow from -12 dB, red from -3 dB), only while
                    // the Sound tab is on screen and the device isn't muted.
                    PwNodePeakMonitor {
                        id: peak
                        node: dev.modelData
                        enabled: devList.view.shown && !(dev.audio && dev.audio.muted)
                    }
                    Column {
                        anchors { left: pick.right; leftMargin: 14; right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 1 }
                        spacing: 1
                        Repeater {
                            model: 2
                            Rectangle {
                                required property int index
                                readonly property real v: {
                                    const ps = peak.peaks && peak.peaks.length ? peak.peaks : [peak.peak, peak.peak];
                                    const p = ps[Math.min(index, ps.length - 1)] || 0;
                                    return p > 0.001 ? Math.max(0, Math.min(1, 1 + (20 * Math.log10(p)) / 60)) : 0;
                                }
                                width: parent.width
                                height: 2
                                radius: 1
                                color: Theme.wash(1)
                                Rectangle {
                                    height: parent.height
                                    radius: 1
                                    width: parent.width * parent.v
                                    color: parent.v > 0.9 ? Theme.red : parent.v > 0.75 ? Theme.orange : Theme.green
                                    Behavior on width { NumberAnimation { duration: Theme.peakFollowMs } }
                                }
                            }
                        }
                    }
                    Slider {
                        anchors { left: pick.right; leftMargin: 10; right: parent.right; rightMargin: 10; bottom: parent.bottom; bottomMargin: 7 }
                        height: 22
                        value: dev.audio ? dev.audio.volume : 0
                        dim: muteBtn.muted
                        fillColor: dev.on ? Qt.alpha(Theme.accent, 0.55) : Theme.wash(4)
                        onMoved: v => { if (dev.audio) dev.audio.volume = v; }
                        onRightClicked: if (dev.audio) dev.audio.muted = !dev.audio.muted
                    }
                }
            }
        }
    }
}

