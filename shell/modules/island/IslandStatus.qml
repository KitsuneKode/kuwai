// Signal bars and a battery, in the theme's colour (as in the reference).
// Each has its own tooltip: the network (name, strength) and the battery
// (charge, plugged in or on battery, time left). No battery, no battery.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Networking
import qs.config
import qs.components
import qs.services

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
    // The island window it sits in (rest or hover); set → right-click menus.
    property var bar: null
    property string mode: ""
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/kuwai/state"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { const m = text().match(/^mode=(\S+)/m); status.mode = m ? m[1] : ""; }
    }
    function hm(s) { const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60); return h ? h + "h " + m + "m" : m + "m"; }

    Item {
        id: netItem
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
        id: batItem
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

    // ── Right-click menus (the island's own menu: components/TrayMenu) ──
    TapHandler {
        enabled: !!status.bar
        acceptedButtons: Qt.RightButton
        onTapped: (point) => {
            const onNet = point.position.x < netItem.x + netItem.width + 6;
            (onNet ? netMenu : batMenu).open = true;
        }
    }
    component Menu: TrayMenu {
        window: status.bar
        property bool counted: false
        onOpenChanged: {
            if (!status.bar) return;
            if (open && !counted) { counted = true; status.bar.menus++; }
            else if (!open && counted) { counted = false; status.bar.menus = Math.max(0, status.bar.menus - 1); }
        }
    }
    Menu {
        id: netMenu
        anchorItem: netItem
        items: {
            const dev = status.wifiDev;
            const nets = dev ? dev.networks.values.filter(n => n.known || n.connected).sort((a, b) => b.signalStrength - a.signalStrength).slice(0, 5) : [];
            const out = [{ text: status.net ? "Connected to " + status.net.name : Networking.wifiEnabled ? "Not connected" : "Wi-Fi is off", enabled: false }];
            for (const n of nets) out.push({
                text: n.name + (n.connected ? "" : "  ·  " + Math.round(n.signalStrength * 100) + "%"),
                glyph: n.connected ? "\u{f012c}" : "\u{f05a9}",
                enabled: !n.connected,
                triggered: () => n.connect()
            });
            out.push({ isSeparator: true });
            out.push({ text: Networking.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on", glyph: Networking.wifiEnabled ? "\u{f05aa}" : "\u{f05a9}", triggered: () => Networking.wifiEnabled = !Networking.wifiEnabled });
            out.push({ text: "Other networks and settings…", glyph: "\u{f0493}", triggered: () => Quickshell.execDetached(["nmgui"]) });
            return out;
        }
    }
    Menu {
        id: batMenu
        anchorItem: batItem
        items: {
            const b = status.battery;
            const left = b && status.hasBattery ? (status.charging ? (b.timeToFull > 0 ? " · full in " + status.hm(b.timeToFull) : " · charging") : (!status.onAC && b.timeToEmpty > 0 ? " · " + status.hm(b.timeToEmpty) + " left" : status.onAC ? " · plugged in" : "")) : "";
            const modes = [["battery", "Battery saver", "\u{f0083}"], ["focus", "Focus", "\u{f04b2}"], ["default", "As designed", "\u{f0e09}"], ["glass", "Glass", "\u{f0e7d}"], ["gaming", "Gaming", "\u{f0297}"]];
            const out = [{ text: status.pct + "%" + left, enabled: false }, { isSeparator: true }];
            for (const m of modes) out.push({
                text: m[1], glyph: status.mode === m[0] ? "\u{f012c}" : m[2],
                triggered: () => Quickshell.execDetached([Paths.bin + "/kuwai", "mode", m[0]])
            });
            out.push({ isSeparator: true });
            out.push({ text: "Power…", glyph: "\u{f0425}", triggered: () => Island.open("power", status.bar ? status.bar.screenName : "", "pointer", "island") });
            return out;
        }
    }
}
