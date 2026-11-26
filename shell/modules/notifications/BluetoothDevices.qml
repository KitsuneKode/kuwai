import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.config
import qs.components
import qs.components.ui as Ui
import qs.services

Item {
    id: bt

    property var stage: null
    property bool scanning: true
    readonly property var adapter: stage ? stage.adapter : Bluetooth.defaultAdapter
    readonly property var devices: stage ? stage.devices : Bluetooth.devices.values
    readonly property bool on: !!adapter && adapter.enabled
    implicitWidth: Theme.panelS
    implicitHeight: col.implicitHeight
    Binding { target: bt.stage ? null : bt.adapter; property: "discovering"; value: true; when: bt.on && bt.visible && bt.scanning && !bt.stage }

    function label(d) { return d.name || d.deviceName || d.address; }
    function named(d) { const n = d.name || d.deviceName || ""; return n !== "" && !/^([0-9A-F]{2}[-:_]){5}[0-9A-F]{2}$/i.test(n); }
    readonly property var mine: on ? devices.filter(d => d.paired || d.connected)
        .sort((x, y) => (y.connected - x.connected) || label(x).localeCompare(label(y))) : []
    readonly property var nearby: on ? devices.filter(d => !d.paired && !d.connected && named(d))
        .sort((x, y) => label(x).localeCompare(label(y))).slice(0, 8) : []
    function busy(d) { return d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting; }
    function act(d) {
        if (!d || busy(d)) return;
        if (!d.paired) { d.trusted = true; d.pair(); }
        else if (d.connected) d.disconnect();
        else d.connect();
    }
    function status(d) {
        if (d.pairing) return "Pairing…";
        if (d.state === BluetoothDeviceState.Connecting) return "Connecting…";
        if (d.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…";
        if (d.connected) return "Connected" + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "");
        return d.paired ? "Not connected" : "Select to pair";
    }

    property var forgetTarget: null
    property Item hoverRow: null
    FluidHighlight { target: bt.hoverRow; radius: Theme.r2 }
    function requestForget(d) {
        if (!d || !d.paired) return;
        forgetTarget = d;
        forgetDialog.open();
    }
    readonly property var all: mine.concat(nearby)
    function confirmForget() {
        const target = forgetTarget;
        forgetTarget = null;
        if (target && all.indexOf(target) >= 0 && target.paired) target.forget();
    }
    ConfirmationDialog {
        id: forgetDialog
        title: "Forget saved configuration?"
        message: bt.forgetTarget ? "Forget " + (bt.forgetTarget.name || "this device") + "? Connecting again will require its credentials or pairing." : ""
        onConfirmed: bt.confirmForget()
        onRejected: bt.forgetTarget = null
    }

    component Section: Label { x: 4; size: Theme.tFootnote; weight: Theme.wMedium; color: Theme.textTertiary }
    component DeviceRow: Rectangle {
        id: row
        required property var dev
        width: col.width
        height: lrow.implicitHeight
        radius: Theme.r2
        color: row.activeFocus && bt.hoverRow !== row ? Theme.rowHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
        activeFocusOnTab: true
        Keys.onReturnPressed: bt.act(row.dev)
        Keys.onEnterPressed: bt.act(row.dev)
        Keys.onSpacePressed: bt.act(row.dev)
        Keys.onDeletePressed: bt.requestForget(row.dev)
        FocusRing { cornerRadius: Theme.r2 }
        MouseArea {
            id: rowArea
            onContainsMouseChanged: {
                if (containsMouse) bt.hoverRow = row;
                else if (bt.hoverRow === row) bt.hoverRow = null;
            }
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: bt.busy(row.dev) ? Qt.BusyCursor : Qt.PointingHandCursor
            onClicked: bt.act(row.dev)
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
            title: bt.label(row.dev)
            sub: bt.status(row.dev)
            subColor: bt.busy(row.dev) ? Theme.accent : row.dev.connected && row.dev.batteryAvailable && row.dev.battery < 0.2 ? Theme.red : Theme.textTertiary
            trailOpacity: row.dev.paired && (rowArea.containsMouse || forget.hovered || row.activeFocus) ? 1 : 0
            trail: RestMark {
                id: forget
                glyph: "\u{f0a7a}"
                tip: "Forget this device (Delete)"
                onClicked: bt.requestForget(row.dev)
            }
        }
        Accessible.role: Accessible.ListItem
        Accessible.name: bt.label(row.dev)
        Accessible.description: bt.status(row.dev)
        Accessible.onPressAction: bt.act(row.dev)
    }

    Column {
        id: col
        width: parent.width
        spacing: Theme.s2

        Ui.EmptyState {
            visible: !bt.on
            width: parent.width
            icon: "bluetooth"
            title: !bt.adapter ? "No Bluetooth adapter." : "Bluetooth is off."
            body: !bt.adapter ? "Connect a Bluetooth adapter to pair devices." : "Turn Bluetooth on above to connect or pair nearby devices."
        }
        Section { visible: bt.mine.length > 0; text: "My devices" }
        Column {
            visible: bt.mine.length > 0
            width: parent.width
            spacing: 2
            Repeater {
                model: ScriptModel { values: bt.mine; comparisonMode: ObjectComparison.Identity }
                delegate: DeviceRow { required property var modelData; dev: modelData }
            }
        }
        Row {
            visible: bt.on
            spacing: Theme.s2
            Section { text: "Nearby" }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: !!bt.adapter && bt.adapter.discovering
                width: 6; height: 6; radius: 3
                color: Theme.accent
                SequentialAnimation on opacity {
                    running: parent.visible && bt.visible && !Theme.reduceMotion
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: Theme.breatheMs * 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSine }
                    NumberAnimation { to: 1; duration: Theme.breatheMs * 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSine }
                }
            }
        }
        Label {
            visible: bt.on && bt.nearby.length === 0
            x: 4
            width: parent.width - 8
            wrapMode: Text.Wrap
            text: "Looking… put the device in pairing mode."
            size: Theme.tSub; color: Theme.textTertiary
        }
        Column {
            visible: bt.nearby.length > 0
            width: parent.width
            spacing: 2
            Repeater {
                model: ScriptModel { values: bt.nearby; comparisonMode: ObjectComparison.Identity }
                delegate: DeviceRow { required property var modelData; dev: modelData }
            }
        }
    }
}
