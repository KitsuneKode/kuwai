// Bluetooth (in the expanded island), signal bars and a battery, in the
// theme's colour (as in the reference). Each has its own tooltip — what's
// connected, the network (name, strength), the battery (charge, time left) —
// and a menu on a click (left or right). No battery, no battery. On a cable
// (or a phone tethered over USB, which is one) with no Wi-Fi up, an Ethernet
// glyph takes the bars' place.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Networking
import Quickshell.Bluetooth
import qs.config
import qs.components
import qs.services

Row {
    id: status
    spacing: 8
    // Status is white, like any status bar: the accent means "where you are"
    // (the current workspace) and nothing else. Colour here only says
    // something: green charging, red low.
    property color tint: Theme.textPrimary

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery && battery.isLaptopBattery && battery.isPresent
    readonly property int pct: hasBattery ? Math.round(battery.percentage > 1 ? battery.percentage : battery.percentage * 100) : 0
    readonly property bool charging: hasBattery && battery.state === UPowerDeviceState.Charging
    readonly property bool onAC: !UPower.onBattery
    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var net: wifiDev ? wifiDev.networks.values.find(n => n.connected) || null : null
    readonly property real signal: net ? net.signalStrength : 0
    readonly property bool wired: !net && Networking.devices.values.some(d => d.type === DeviceType.Wired && d.connected)
    // The island window it sits in (rest or hover); set → click menus.
    property var bar: null
    // Bluetooth shows in the expanded island (at rest it would crowd it).
    property bool showBluetooth: false
    // The lock and login screens: Bluetooth whenever it's on, and the charge
    // as a number beside the battery.
    property bool bluetoothWhenOn: false
    property bool showPercent: false
    // What the battery shows, if not the charge (LockCorner's plug-in sweep).
    property real shownPct: -1
    readonly property real drawnPct: shownPct >= 0 ? shownPct : pct
    readonly property Item batteryItem: batItem
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected)
    property string mode: ""
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/kuwai/state"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { const m = text().match(/^mode=(\S+)/m); status.mode = m ? m[1] : ""; }
    }
    function hm(s) { const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60); return h ? h + "h " + m + "m" : m + "m"; }

    Item {
        id: btItem
        visible: !!status.bt && (status.showBluetooth || (status.bluetoothWhenOn && status.bt.enabled))
        width: 14; height: 14
        anchors.verticalCenter: parent.verticalCenter
        Text {
            anchors.centerIn: parent
            // On with something connected / on / off.
            text: !status.bt || !status.bt.enabled ? "\u{f00b2}" : status.btConnected.length ? "\u{f00b1}" : "\u{f00af}"
            font.family: Theme.fontGlyph; font.pixelSize: 14
            color: status.bt && status.bt.enabled ? (status.btConnected.length ? status.tint : Qt.alpha(status.tint, 0.6)) : Qt.alpha(status.tint, 0.3)
        }
        HoverHandler { id: btHover; cursorShape: status.bar ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: !!status.bar; acceptedButtons: Qt.LeftButton | Qt.RightButton; onTapped: btMenu.open = !btMenu.open }
        Tip {
            text: !status.bt ? "" : !status.bt.enabled ? "Bluetooth is off"
                : status.btConnected.length ? status.btConnected.map(d => (d.name || d.deviceName) + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "")).join("  ·  ")
                : "Bluetooth · nothing connected"
            shown: btHover.hovered && !btMenu.open
            below: true
        }
    }
    Item {
        id: netItem
        width: status.wired ? 14 : bars.width; height: 14
        anchors.verticalCenter: parent.verticalCenter
        Text {
            visible: status.wired
            anchors.centerIn: parent
            text: "\u{f0200}"
            font.family: Theme.fontGlyph; font.pixelSize: 14
            color: status.tint
        }
        Row {
            id: bars
            visible: !status.wired
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
        HoverHandler { id: netHover; cursorShape: status.bar ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: !!status.bar; acceptedButtons: status.showBluetooth ? Qt.LeftButton | Qt.RightButton : Qt.RightButton; onTapped: netMenu.open = !netMenu.open }
        Tip {
            text: status.wired ? "Wired" : !status.wifiDev ? "No Wi-Fi" : status.net ? status.net.name + " · " + Math.round(status.signal * 100) + "%" : "Not connected"
            shown: netHover.hovered && !netMenu.open
            below: true
        }
    }
    Label {
        visible: status.showPercent && status.hasBattery
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(status.drawnPct) + "%"
        size: 12; weight: Theme.wMedium
        color: status.shownPct >= 0 ? Theme.positive : status.tint
        font.features: ({ "tnum": 1 })
    }
    Item {
        id: batItem
        visible: status.hasBattery
        anchors.verticalCenter: parent.verticalCenter
        width: 27; height: 13
        Rectangle { anchors.fill: parent; anchors.rightMargin: 2; radius: 4; color: Qt.alpha(status.tint, 0.22) }
        Rectangle {
            height: parent.height; radius: 4
            width: Math.max(5, (parent.width - 2) * status.drawnPct / 100)
            color: status.pct <= 20 && !status.onAC ? Theme.critical : status.charging ? Theme.positive : status.tint
            Behavior on width { enabled: status.shownPct < 0; NumberAnimation { duration: Theme.glideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
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
        HoverHandler { id: batHover; cursorShape: status.bar ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: !!status.bar; acceptedButtons: status.showBluetooth ? Qt.LeftButton | Qt.RightButton : Qt.RightButton; onTapped: batMenu.open = !batMenu.open }
        Tip {
            text: status.pct + "% · " + (status.charging ? "Charging" + (status.battery.timeToFull > 0 ? ", full in " + status.hm(status.battery.timeToFull) : "")
                  : status.onAC ? "Plugged in" : "On battery" + (status.battery.timeToEmpty > 0 ? ", " + status.hm(status.battery.timeToEmpty) + " left" : ""))
            shown: batHover.hovered && !batMenu.open
            below: true
        }
    }

    // ── Menus (the island's own: components/TrayMenu) ──────────────────
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
            // Everything in range (the scanner runs while this is open), one
            // row per name: connected, then saved, then by strength.
            const seen = {};
            const nets = (dev ? dev.networks.values : [])
                .filter(n => n.name && !seen[n.name] && (seen[n.name] = true))
                .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
                .slice(0, 8);
            const secured = n => n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
            const out = [{ text: status.net ? "Connected to " + status.net.name : Networking.wifiEnabled ? (nets.length ? "Not connected" : "Looking for networks…") : "Wi-Fi is off", enabled: false }];
            if (Networking.wifiEnabled) for (const n of nets) out.push({
                text: n.name + (n.connected ? "" : "  ·  " + Math.round(n.signalStrength * 100) + "%" + (n.known ? "  ·  saved" : secured(n) ? "  ·  locked" : "")),
                glyph: n.connected ? "\u{f012c}" : secured(n) && !n.known ? "\u{f033e}" : "\u{f05a9}",
                enabled: !n.connected,
                // A new locked network needs its password: Controls asks for it.
                triggered: () => { if (n.known || !secured(n)) n.connect(); else Notifs.toggleCenter("controls", "pointer", status.bar ? status.bar.screenName : ""); }
            });
            out.push({ isSeparator: true });
            out.push({ text: Networking.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on", glyph: Networking.wifiEnabled ? "\u{f05aa}" : "\u{f05a9}", triggered: () => Networking.wifiEnabled = !Networking.wifiEnabled });
            out.push({ text: "Wi-Fi settings…", glyph: "\u{f0493}", triggered: () => Notifs.toggleCenter("controls", "pointer", status.bar ? status.bar.screenName : "") });
            return out;
        }
    }
    Binding { target: status.wifiDev; property: "scannerEnabled"; value: true; when: status.wifiDev !== null && netMenu.open }
    Menu {
        id: btMenu
        anchorItem: btItem
        items: {
            const a = status.bt;
            if (!a) return [{ text: "No Bluetooth", enabled: false }];
            const devs = Bluetooth.devices.values.filter(d => d.paired || d.connected)
                .sort((x, y) => (y.connected - x.connected) || String(x.name).localeCompare(String(y.name)));
            const out = [{ text: a.enabled ? (status.btConnected.length ? status.btConnected.length + " connected" : "Bluetooth on") : "Bluetooth is off", enabled: false }];
            if (a.enabled) for (const d of devs) out.push({
                text: (d.name || d.deviceName) + (d.connected && d.batteryAvailable ? "  ·  " + Math.round(d.battery * 100) + "%" : d.connected ? "" : "  ·  connect"),
                glyph: d.connected ? "\u{f012c}" : "\u{f00af}",
                triggered: () => { if (d.connected) d.disconnect(); else d.connect(); }
            });
            out.push({ isSeparator: true });
            out.push({ text: a.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on", glyph: a.enabled ? "\u{f00b2}" : "\u{f00af}", triggered: () => a.enabled = !a.enabled });
            out.push({ text: "Bluetooth settings…", glyph: "\u{f0493}", triggered: () => Quickshell.execDetached(["blueman-manager"]) });
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
