// Bluetooth, grown out of the island (the menu's "Bluetooth…", or
// Island.open("bluetooth")): on/off, your devices, and new ones nearby while
// it looks. Replaces blueman for the everyday things: pair, connect,
// disconnect, forget. Nothing here closes the panel; rows say what's
// happening (connecting…, pairing…) as it happens.
//   ↑ ↓ choose · ↵ connect / disconnect / pair · Del forget · Esc back
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.config
import qs.components
import qs.services

FocusScope {
    id: bp
    focus: true
    implicitWidth: 420
    implicitHeight: col.implicitHeight + 36

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: !!adapter && adapter.enabled
    // Look for new devices while the panel is open (and only then: scanning
    // costs radio time and battery).
    Binding { target: bp.adapter; property: "discovering"; value: true; when: bp.on && bp.visible }

    function label(d) { return d.name || d.deviceName || d.address; }
    readonly property var mine: on ? Bluetooth.devices.values.filter(d => d.paired || d.connected)
        .sort((x, y) => (y.connected - x.connected) || label(x).localeCompare(label(y))) : []
    // Nearby: named only (a list of MAC addresses helps nobody).
    readonly property var nearby: on ? Bluetooth.devices.values.filter(d => !d.paired && !d.connected && (d.name || d.deviceName))
        .sort((x, y) => label(x).localeCompare(label(y))).slice(0, 8) : []
    readonly property var all: mine.concat(nearby)
    property int sel: 0
    onAllChanged: sel = Math.min(sel, Math.max(0, all.length - 1))

    function busy(d) { return d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting; }
    function act(d) {
        if (!d || busy(d)) return;
        if (!d.paired) { d.trusted = true; d.pair(); }      // connects once paired (BlueZ)
        else if (d.connected) d.disconnect();
        else d.connect();
    }
    function status(d) {
        if (d.pairing) return "Pairing…";
        if (d.state === BluetoothDeviceState.Connecting) return "Connecting…";
        if (d.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…";
        if (d.connected) return "Connected" + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "");
        return d.paired ? "Not connected" : "Tap to pair";
    }

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Down) sel = Math.min(all.length - 1, sel + 1);
        else if (e.key === Qt.Key_Up) sel = Math.max(0, sel - 1);
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) act(all[sel]);
        else if (e.key === Qt.Key_Delete && all[sel] && all[sel].paired) all[sel].forget();
        else return;
        e.accepted = true;
    }

    Column {
        id: col
        x: 18; y: 18
        width: bp.width - 36
        spacing: 12

        Item {
            width: parent.width
            height: 26
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Bluetooth"
                size: Theme.tTitle3; weight: Theme.wSemibold
            }
            Toggle {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                enabled: !!bp.adapter
                on: bp.on
                label: "Bluetooth"
                onToggled: if (bp.adapter) bp.adapter.enabled = !bp.adapter.enabled
            }
        }

        Label {
            visible: !bp.on
            width: parent.width
            text: !bp.adapter ? "No Bluetooth adapter." : "Bluetooth is off."
            size: Theme.tBody; color: Theme.textTertiary
        }

        component Section: Label {
            size: Theme.tFootnote; weight: Theme.wMedium; color: Theme.textTertiary
        }
        component DeviceRow: Rectangle {
            id: row
            required property var dev
            required property int at
            width: col.width
            height: 46
            radius: Theme.r2
            color: rowArea.containsMouse || bp.sel === at ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
            Icon {
                id: ic
                x: 10; anchors.verticalCenter: parent.verticalCenter
                name: String(row.dev.icon || "").indexOf("audio") >= 0 ? "headphones"
                    : String(row.dev.icon || "").indexOf("input") >= 0 ? "keyboard" : "bluetooth"
                size: 18
                color: row.dev.connected ? Theme.accent : Theme.textSecondary
            }
            Column {
                anchors { left: ic.right; leftMargin: 12; right: acts.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 2
                Label { width: parent.width; elide: Text.ElideRight; text: bp.label(row.dev); size: Theme.tBody; weight: Theme.wSemibold }
                Label {
                    width: parent.width; elide: Text.ElideRight
                    text: bp.status(row.dev)
                    size: Theme.tFootnote
                    color: bp.busy(row.dev) ? Theme.accent : Theme.textTertiary
                }
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: bp.busy(row.dev) ? Qt.BusyCursor : Qt.PointingHandCursor
                onClicked: { bp.sel = row.at; bp.act(row.dev); }
            }
            // Forget: only on hover or selection, so the list reads calm.
            Row {
                id: acts
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                visible: row.dev.paired && (rowArea.containsMouse || forget.hovered || bp.sel === row.at)
                RestMark {
                    id: forget
                    glyph: "\u{f0a7a}"
                    tip: "Forget this device"
                    onClicked: row.dev.forget()
                }
            }
        }

        Section { visible: bp.mine.length > 0; text: "My devices" }
        Column {
            visible: bp.mine.length > 0
            width: parent.width
            spacing: 2
            Repeater {
                model: ScriptModel { values: bp.mine; comparisonMode: ObjectComparison.Identity }
                delegate: DeviceRow { required property var modelData; required property int index; dev: modelData; at: index }
            }
        }

        Row {
            visible: bp.on
            spacing: 8
            Section { text: "Nearby" }
            // Looking: a slow breathing dot, not a spinner (it never "finishes").
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: bp.adapter && bp.adapter.discovering
                width: 6; height: 6; radius: 3
                color: Theme.accent
                SequentialAnimation on opacity {
                    running: parent.visible && bp.visible && !Theme.reduceMotion
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: Theme.breatheMs * 2; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: Theme.breatheMs * 2; easing.type: Easing.InOutSine }
                }
            }
        }
        Label {
            visible: bp.on && bp.nearby.length === 0
            text: "Looking… put the device in pairing mode."
            size: Theme.tSub; color: Theme.textTertiary
        }
        Column {
            visible: bp.nearby.length > 0
            width: parent.width
            spacing: 2
            Repeater {
                model: ScriptModel { values: bp.nearby; comparisonMode: ObjectComparison.Identity }
                delegate: DeviceRow { required property var modelData; required property int index; dev: modelData; at: bp.mine.length + index }
            }
        }
    }
}
