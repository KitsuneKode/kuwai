// A level with its number: title left, the big value right, a bar, a line
// of detail. Accent until it's high (orange > 75 %, red > 90 %).
//
//   Meter { title: "Memory"; value: 0.62; detail: "9.8 of 16 GB" }
import QtQuick
import qs.config
import qs.components

Column {
    id: m
    property string title
    property real value
    property string big: Math.round(value * 100) + "%"
    property string detail

    width: parent ? parent.width : 400
    spacing: 6
    Item {
        width: parent.width; height: 26
        Label { anchors.verticalCenter: parent.verticalCenter; text: m.title; size: 11; weight: Theme.wMedium; color: Theme.textTertiary }
        Label { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: m.big; size: 20; weight: Theme.wSemibold; rounded: true; font.features: ({ "tnum": 1 }) }
    }
    Item {
        width: parent.width; height: 8
        Rectangle { anchors.fill: parent; radius: 4; color: Theme.platterDim }
        Rectangle {
            width: Math.max(8, parent.width * Math.min(1, m.value)); height: parent.height; radius: 4
            color: m.value > 0.9 ? Theme.red : m.value > 0.75 ? Theme.orange : Theme.accent
            Behavior on width { NumberAnimation { duration: Theme.glideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        }
    }
    Label { visible: text !== ""; text: m.detail; size: 11; color: Theme.textTertiary }
    Accessible.role: Accessible.ProgressBar
    Accessible.name: m.title + " " + m.big
}
