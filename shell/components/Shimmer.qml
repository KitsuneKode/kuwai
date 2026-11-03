// Text with a highlight sweeping through it while something is in progress
// (AI Elements' shimmer, T3 Code's live-tool shine): the words stay still, a
// soft band of brighter text passes over them every 1.8 s. Off when `active`
// is false or motion is reduced: then it's plain text.
import QtQuick
import QtQuick.Effects
import qs.config

Item {
    id: root
    property alias text: base.text
    property int size: 13
    property color color: Theme.textTertiary
    property color shine: Theme.textPrimary
    property bool active: true
    property int weight: Theme.wRegular

    implicitWidth: base.implicitWidth
    implicitHeight: base.implicitHeight

    Label {
        id: base
        size: root.size
        weight: root.weight
        color: root.color
        layer.enabled: sweep.visible
    }
    Item {
        id: band
        anchors.fill: base
        visible: false
        layer.enabled: true
        Rectangle {
            width: Math.max(48, base.width * 0.45)
            height: parent.height
            x: -width + pos * (parent.width + width)
            property real pos: 0
            NumberAnimation on pos {
                running: sweep.visible
                from: 0; to: 1
                duration: 1800
                loops: Animation.Infinite
                easing.type: Easing.InOutSine
            }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: root.shine }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }
    MultiEffect {
        id: sweep
        visible: root.active && root.visible && !Theme.reduceMotion
        anchors.fill: base
        source: band
        maskEnabled: true
        maskSource: base
    }
}
