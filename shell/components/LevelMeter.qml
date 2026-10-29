// A stereo level meter for a PipeWire node: one bar per channel, green up
// to -12 dB, yellow to -3 dB, red above, with a peak-hold tick that falls
// back slowly. Runs only while visible.
//
//   LevelMeter { node: Pipewire.defaultAudioSink; height: 160 }
import QtQuick
import Quickshell.Services.Pipewire
import qs.config

Item {
    id: m

    property var node: null
    property bool active: visible
    readonly property var peaks: monitor.peaks && monitor.peaks.length ? monitor.peaks : [monitor.peak, monitor.peak]

    implicitWidth: 12
    implicitHeight: 160

    PwNodePeakMonitor {
        id: monitor
        node: m.node
        enabled: m.active && m.node !== null
    }

    // Peaks are linear amplitude; show them on a dB scale (-60..0 dB).
    function level(a) {
        if (!(a > 0)) return 0;
        const db = 20 * Math.log10(a);
        return Math.max(0, Math.min(1, (db + 60) / 60));
    }

    Row {
        anchors.fill: parent
        spacing: 2
        Repeater {
            model: Math.min(2, m.peaks.length)
            Item {
                id: bar
                required property int index
                readonly property real lv: m.level(m.peaks[index] || 0)
                property real hold: 0
                onLvChanged: if (lv > hold) { hold = lv; holdFall.restart(); }
                width: (m.width - 2) / 2
                height: m.height

                Rectangle {
                    anchors.fill: parent
                    radius: 2
                    color: Qt.rgba(1, 1, 1, 0.06)
                }
                // The lit part, clipped from a full-height gradient.
                Item {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: parent.height * bar.lv
                    clip: true
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: bar.height
                        radius: 2
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Theme.red }
                            GradientStop { position: 0.06; color: Theme.red }
                            GradientStop { position: 0.07; color: Theme.yellow }
                            GradientStop { position: 0.20; color: Theme.yellow }
                            GradientStop { position: 0.21; color: Theme.green }
                            GradientStop { position: 1.0; color: Theme.green }
                        }
                    }
                }
                Rectangle {
                    visible: bar.hold > 0.02
                    width: parent.width
                    height: 2
                    y: parent.height * (1 - bar.hold)
                    color: Qt.rgba(1, 1, 1, 0.7)
                }
                NumberAnimation { id: holdFall; target: bar; property: "hold"; to: 0; duration: 1600; easing.type: Easing.InQuad }
            }
        }
    }
}
