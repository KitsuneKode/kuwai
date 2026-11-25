import QtQuick
import qs.config

Item {
    id: bar
    property real value: 0
    property bool dim: false
    property color fillColor: dim ? Theme.fillDim : Theme.fill
    property color trackColor: Theme.track
    property bool glide: true

    property real shown: Math.max(0, Math.min(1, value))
    Behavior on shown { enabled: bar.glide && !Theme.reduceMotion; NumberAnimation { duration: Theme.glideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

    implicitHeight: 6
    Accessible.role: Accessible.ProgressBar

    Rectangle { anchors.fill: parent; radius: height / 2; color: bar.trackColor }
    Rectangle {
        width: Math.max(height, bar.width * bar.shown)
        height: bar.height
        radius: height / 2
        visible: bar.shown > 0.004
        color: bar.fillColor
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
    }
}
