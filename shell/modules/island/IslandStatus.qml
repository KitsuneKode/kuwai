// Signal bars and a battery, in the theme's colour (as in the reference).
// Each has its own tooltip: the network (name, strength) and the battery
// (charge, plugged in or on battery, time left). No battery, no battery.
import QtQuick
import Quickshell.Services.UPower
import Quickshell.Networking
import qs.config
import qs.components

Row {
    id: status
    spacing: 8
    property color tint: Theme.accent

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery && battery.isLaptopBattery && battery.isPresent
    readonly property int pct: hasBattery ? Math.round(battery.percentage > 1 ? battery.percentage : battery.percentage * 100) : 0
    readonly property bool charging: hasBattery && battery.state === UPowerDeviceState.Charging
    readonly property bool onAC: !UPower.onBattery
    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var net: wifiDev ? wifiDev.networks.values.find(n => n.connected) || null : null
    readonly property real signal: net ? net.signalStrength : 0
    function hm(s) { const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60); return h ? h + "h " + m + "m" : m + "m"; }

    Item {
        width: bars.width; height: 14
        anchors.verticalCenter: parent.verticalCenter
        Row {
            id: bars
            anchors.bottom: parent.bottom
            spacing: 2
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    anchors.bottom: parent.bottom
                    width: 3; radius: 1
                    height: 4 + index * 3
                    color: status.net && status.signal > index * 0.25 ? status.tint : Qt.alpha(status.tint, 0.25)
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                }
            }
        }
        HoverHandler { id: netHover }
        Tip {
            text: !status.wifiDev ? "No Wi-Fi" : status.net ? status.net.name + " · " + Math.round(status.signal * 100) + "%" : "Not connected"
            shown: netHover.hovered
            below: true
        }
    }
    Item {
        visible: status.hasBattery
        anchors.verticalCenter: parent.verticalCenter
        width: 27; height: 13
        Rectangle { anchors.fill: parent; anchors.rightMargin: 2; radius: 4; color: Qt.alpha(status.tint, 0.22) }
        Rectangle {
            height: parent.height; radius: 4
            width: Math.max(5, (parent.width - 2) * status.pct / 100)
            color: status.pct <= 20 && !status.onAC ? Theme.red : status.tint
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        }
        Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 2; height: 5; radius: 1; color: Qt.alpha(status.tint, 0.45) }
        Text {
            visible: status.onAC
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -1
            text: "\u{f140b}"
            font.family: Theme.fontGlyph
            font.pixelSize: 10
            color: "#0b0b0d"
        }
        HoverHandler { id: batHover }
        Tip {
            text: status.pct + "% · " + (status.charging ? "Charging" + (status.battery.timeToFull > 0 ? ", full in " + status.hm(status.battery.timeToFull) : "")
                  : status.onAC ? "Plugged in" : "On battery" + (status.battery.timeToEmpty > 0 ? ", " + status.hm(status.battery.timeToEmpty) + " left" : ""))
            shown: batHover.hovered
            below: true
        }
    }
}
