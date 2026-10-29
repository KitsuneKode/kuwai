// Signal bars and a battery that fills, Apple-style. Wi-Fi from NetworkManager
// (Quickshell.Networking), battery from UPower; no battery, no battery glyph.
import QtQuick
import Quickshell.Services.UPower
import Quickshell.Networking
import qs.config

Row {
    id: status
    spacing: 8

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery && battery.isLaptopBattery && battery.isPresent
    readonly property int pct: hasBattery ? Math.round(battery.percentage > 1 ? battery.percentage : battery.percentage * 100) : 0
    readonly property bool charging: hasBattery && battery.state === UPowerDeviceState.Charging
    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var net: wifiDev ? wifiDev.networks.values.find(n => n.connected) || null : null
    readonly property real signal: net ? net.signalStrength : 0

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        height: 12
        Repeater {
            model: 4
            Rectangle {
                required property int index
                anchors.bottom: parent.bottom
                width: 3; radius: 1
                height: 4 + index * 2.6
                color: status.net && status.signal > index * 0.25 ? "white" : Qt.rgba(1, 1, 1, 0.25)
            }
        }
    }
    Item {
        visible: status.hasBattery
        anchors.verticalCenter: parent.verticalCenter
        width: 26; height: 12
        Rectangle { anchors.fill: parent; anchors.rightMargin: 2; radius: 4; color: Qt.rgba(1, 1, 1, 0.22) }
        Rectangle {
            height: parent.height; radius: 4
            width: Math.max(4, (parent.width - 2) * status.pct / 100)
            color: status.charging ? Theme.green : status.pct <= 20 ? Theme.red : "white"
        }
        Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 2; height: 5; radius: 1; color: Qt.rgba(1, 1, 1, 0.4) }
        Text {
            visible: status.charging
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -1
            text: "\u{f140b}"
            font.family: Theme.fontGlyph
            font.pixelSize: 9
            color: "black"
        }
    }
}
