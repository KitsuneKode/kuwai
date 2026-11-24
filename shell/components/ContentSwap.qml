import QtQuick
import qs.config

Item {
    id: swap
    property string key: ""
    property real enterScale: 0.985
    default property alias content: host.data

    implicitWidth: host.implicitWidth
    implicitHeight: host.implicitHeight

    Item {
        id: host
        anchors.fill: parent
        transformOrigin: Item.Top
    }

    onKeyChanged: {
        if (Theme.reduceMotion) {
            host.opacity = 1;
            host.scale = 1;
            return;
        }
        reveal.restart();
    }

    ParallelAnimation {
        id: reveal
        NumberAnimation {
            target: host
            property: "opacity"
            from: 0.2
            to: 1.0
            duration: Theme.enterMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.easeOut
        }
        NumberAnimation {
            target: host
            property: "scale"
            from: swap.enterScale
            to: 1.0
            duration: Theme.enterMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.easeOut
        }
    }
}
