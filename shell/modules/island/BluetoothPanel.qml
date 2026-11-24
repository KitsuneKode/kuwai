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
import qs.components.ui as Ui
import qs.services

FocusScope {
    id: bp

    property var forgetTarget: null
    function requestForget(target) {
        if (!target || !target.paired) return;
        forgetTarget = target;
        forgetDialog.open();
    }
    function confirmForget() {
        const target = forgetTarget;
        forgetTarget = null;
        if (target && all.indexOf(target) >= 0 && target.paired) target.forget();
    }
    ConfirmationDialog {
        id: forgetDialog
        title: "Forget saved configuration?"
        message: bp.forgetTarget ? "Forget " + (bp.forgetTarget.name || "this device") + "? Connecting again will require its credentials or pairing." : ""
        onConfirmed: bp.confirmForget()
        onRejected: bp.forgetTarget = null
    }
    focus: true
    implicitWidth: Theme.panelS
    // Up to what the island gives; past that (many devices, a large Text
    // size) the list scrolls, with the shell's fade.
    readonly property real ceiling: Math.min(Theme.panelMaxH, Theme.screenSize(Screen, "height", 1080) - 64)
    implicitHeight: Math.min(col.implicitHeight + 36, ceiling)

    // The rehearsal's adapter and devices (plain objects; tests/ui/scenes.json).
    property var stage: null
    readonly property var adapter: stage ? stage.adapter : Bluetooth.defaultAdapter
    readonly property var devices: stage ? stage.devices : Bluetooth.devices.values
    readonly property bool on: !!adapter && adapter.enabled
    // Look for new devices while the panel is open (and only then: scanning
    // costs radio time and battery).
    Binding { target: bp.stage ? null : bp.adapter; property: "discovering"; value: true; when: bp.on && bp.visible && !bp.stage }

    function label(d) { return d.name || d.deviceName || d.address; }
    readonly property var mine: on ? bp.devices.filter(d => d.paired || d.connected)
        .sort((x, y) => (y.connected - x.connected) || label(x).localeCompare(label(y))) : []
    // Nearby: named only (a list of MAC addresses helps nobody).
    function named(d) { const n = d.name || d.deviceName || ""; return n !== "" && !/^([0-9A-F]{2}[-:_]){5}[0-9A-F]{2}$/i.test(n); }
    readonly property var nearby: on ? bp.devices.filter(d => !d.paired && !d.connected && named(d))
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
        else if (e.key === Qt.Key_Delete && all[sel] && all[sel].paired) bp.requestForget(all[sel]);
        else return;
        e.accepted = true;
    }

    ScrollFade { flickable: btFlick }
    ScrollHint { flickable: btFlick; anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 4 } }
    Flickable {
        id: btFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 36
        interactive: contentHeight > height + 1
        boundsBehavior: Flickable.StopAtBounds
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

            Ui.EmptyState {
                visible: !bp.on
                width: parent.width
                icon: "bluetooth"
                title: !bp.adapter ? "No Bluetooth adapter." : "Bluetooth is off."
                body: !bp.adapter ? "Connect a Bluetooth adapter to pair devices." : "Turn Bluetooth on above to connect or pair nearby devices."
            }

            component Section: Label {
                size: Theme.tFootnote; weight: Theme.wMedium; color: Theme.textTertiary
            }
            // A device: the shared row (components/ListRow), its kind's mark in the
            // accent while connected, its name, what it's doing; Forget on hover or
            // selection. Rows grow with the text (fixed 46 px rows ran into each
            // other at 200 %).
            component DeviceRow: Rectangle {
                id: row
                required property var dev
                required property int at
                width: col.width
                height: lrow.implicitHeight
                radius: Theme.r2
                color: rowArea.containsMouse || bp.sel === at ? Theme.rowHover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: bp.busy(row.dev) ? Qt.BusyCursor : Qt.PointingHandCursor
                    onClicked: { bp.sel = row.at; bp.act(row.dev); }
                }
                ListRow {
                    id: lrow
                    width: parent.width
                    lead: Icon {
                        anchors.centerIn: parent
                        name: String(row.dev.icon || "").indexOf("audio") >= 0 ? "headphones"
                            : String(row.dev.icon || "").indexOf("mouse") >= 0 ? "mouse"
                            : String(row.dev.icon || "").indexOf("input") >= 0 ? "keyboard"
                            : String(row.dev.icon || "").indexOf("phone") >= 0 ? "device-mobile" : "bluetooth"
                        size: Theme.glyphM
                        color: row.dev.connected ? Theme.accent : Theme.textSecondary
                    }
                    title: bp.label(row.dev)
                    sub: bp.status(row.dev)
                    subColor: bp.busy(row.dev) ? Theme.accent : Theme.textTertiary
                    trailOpacity: row.dev.paired && (rowArea.containsMouse || forget.hovered || bp.sel === row.at) ? 1 : 0
                    trail: RestMark {
                        id: forget
                        glyph: "\u{f0a7a}"
                        tip: "Forget this device"
                        onClicked: bp.requestForget(row.dev)
                    }
                }
                Accessible.role: Accessible.ListItem
                Accessible.name: bp.label(row.dev)
                Accessible.description: bp.status(row.dev)
                Accessible.selected: bp.sel === row.at
                Accessible.onPressAction: { bp.sel = row.at; bp.act(row.dev); }
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
}
