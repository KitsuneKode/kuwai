// The center's Controls tab (Control Center's job):
//
//   [ Wi‑Fi ] [ Bluetooth ]          toggle tiles: tap toggles; tinted when on
//   [ Focus ] [ Night Shift ]        (Apple's blue, Focus indigo, Night orange,
//   [ Caffeine ] [ Power mode ]       Caffeine yellow)
//   Battery     82% · 2h 10m left · charging
//   Brightness  one slider per monitor
//   Warmth      Night Shift colour temperature
//   Bluetooth   paired devices with battery; tap to connect / disconnect
//
// Wi‑Fi: Quickshell.Networking (NetworkManager). Bluetooth: Quickshell's
// BlueZ binding. Battery / power profile: UPower. Brightness: the brightness
// controller; Night Shift: Hyprland's hyprsunset (services/Display).
// Caffeine: an idle inhibitor (services/Caffeine).
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import qs.config
import qs.components
import qs.components.ui
import qs.services

Item {
    id: view

    required property var center
    property bool hosting: true
    readonly property bool shown: hosting && center.open && center.tab === "controls"
    Binding { target: Display; property: "watching"; value: view.shown; when: view.hosting }
    Component.onCompleted: Hyprland.refreshMonitors()

    function key(event, queryEmpty) { return false; }
    function reset() { flick.contentY = 0; wifiOpen = false; }
    function selectFirst() {}
    // Esc: the password field, then the network list, then (false) close.
    function back() {
        if (wifiList.back()) return true;
        if (wifiOpen) { wifiOpen = false; return true; }
        return false;
    }
    // Typing a search opens the network list, so a network can be found.
    property bool wifiOpen: false
    Connections {
        target: view.center
        function onQueryChanged() { if (view.shown && view.center.query !== "") view.wifiOpen = true; }
    }

    function modelOf(name) {
        const m = Hyprland.monitors.values.find(x => x.name === name);
        const o = m && m.lastIpcObject ? m.lastIpcObject : {};
        return o.model || "";
    }

    // ── State ────────────────────────────────────────────────────────────
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var wifiNetwork: wifiDevice ? wifiDevice.networks.values.find(n => n.connected) || null : null
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var btDevices: Bluetooth.devices.values.filter(d => d.paired || d.connected)
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    readonly property var btConnected: btDevices.filter(d => d.connected)
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery && battery.isLaptopBattery && battery.isPresent
    function pct(p) { return Math.round((p > 1 ? p : p * 100)); }
    function duration(s) {
        if (!(s > 0)) return "";
        const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
        return h ? `${h}h ${m}m` : `${m}m`;
    }
    readonly property var profiles: [
        { id: PowerProfile.PowerSaver, label: "Saver" },
        { id: PowerProfile.Balanced, label: "Balanced" },
        { id: PowerProfile.Performance, label: "Performance" }
    ]
    // power-profiles-daemon may be absent or masked (TLP, auto-cpufreq…):
    // then there's no Power tile rather than one that does nothing.
    property bool profilesAvailable: false
    Process {
        running: true
        command: ["busctl", "--system", "status", "org.freedesktop.UPower.PowerProfiles"]
        onExited: code => view.profilesAvailable = code === 0
    }
    readonly property var mic: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [view.mic].filter(n => n) }
    readonly property bool micMuted: mic && mic.audio ? mic.audio.muted : false

    readonly property string profileLabel: (profiles.find(p => p.id === PowerProfiles.profile) || profiles[1]).label

    readonly property real naturalHeight: column.implicitHeight + 8
    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentHeight: column.implicitHeight + 8
        boundsBehavior: Flickable.DragAndOvershootBounds

        Column {
            id: column
            width: parent.width
            spacing: 22

            // ── Toggles ──────────────────────────────────────────────────
            Grid {
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 8
                opacity: view.center.revealAt(60)

                Tile {
                    glyph: Networking.wifiEnabled ? "\u{f05a9}" : "\u{f05aa}"
                    title: "Wi‑Fi"
                    subtitle: !Networking.wifiEnabled ? "Off" : view.wifiNetwork ? view.wifiNetwork.name : "Not connected"
                    on: Networking.wifiEnabled
                    tone: Theme.blue
                    expandable: true
                    moreText: "Show networks"
                    expanded: view.wifiOpen
                    onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                    onOpened: view.wifiOpen = !view.wifiOpen
                }
                Tile {
                    glyph: view.adapter && view.adapter.enabled ? "\u{f00af}" : "\u{f00b2}"
                    title: "Bluetooth"
                    subtitle: !(view.adapter && view.adapter.enabled) ? "Off"
                            : view.btConnected.length === 1 ? view.btConnected[0].name
                            : view.btConnected.length ? view.btConnected.length + " connected" : "On"
                    on: !!(view.adapter && view.adapter.enabled)
                    tone: Theme.blue
                    onToggled: if (view.adapter) view.adapter.enabled = !view.adapter.enabled
                }
                Tile {
                    glyph: "\u{f0594}"
                    title: "Do Not Disturb"
                    subtitle: Notifs.dnd ? "On" : "Off"
                    on: Notifs.dnd
                    tone: "#5e5ce6"
                    onToggled: Notifs.dnd = !Notifs.dnd
                }
                Tile {
                    glyph: Display.nightOn ? "\u{f0594}" : "\u{f05a8}"
                    title: "Night Shift"
                    subtitle: Display.nightOn ? Display.temperature + " K" : "Off"
                    on: Display.nightOn
                    tone: Theme.orange
                    onToggled: Display.toggleNight()
                }
                Tile {
                    glyph: "\u{f0176}"                                   // coffee
                    title: "Caffeine"
                    subtitle: Caffeine.on ? "Staying awake" : "Off"
                    on: Caffeine.on
                    tone: Theme.yellow
                    onToggled: Caffeine.on = !Caffeine.on
                }
                Tile {
                    glyph: view.micMuted ? "\u{f036d}" : "\u{f036c}"
                    title: "Microphone"
                    subtitle: view.micMuted ? "Muted" : (view.mic ? (view.mic.nickname || view.mic.description || "On") : "None")
                    on: !view.micMuted && view.mic !== null
                    tone: Theme.green
                    onToggled: if (view.mic && view.mic.audio) view.mic.audio.muted = !view.mic.audio.muted
                }
                Tile {
                    glyph: "\u{f04c5}"                                  // speedometer (f1b35 isn't in the font)
                    title: "Reduce Motion"
                    subtitle: Theme.reduceMotion ? (Theme.envReduce || Theme.hyprStill ? "On (system)" : "On") : "Off"
                    on: Theme.reduceMotion
                    tone: "#64d2ff"
                    onToggled: Theme.setReduceMotion(!Theme.reduceMotion)
                }
                Tile {
                    visible: view.profilesAvailable
                    glyph: PowerProfiles.profile === PowerProfile.Performance ? "\u{f04c5}"
                         : PowerProfiles.profile === PowerProfile.PowerSaver ? "\u{f032a}" : "\u{f0a7a}"
                    title: "Power"
                    subtitle: view.profileLabel
                    on: PowerProfiles.profile !== PowerProfile.Balanced
                    tone: PowerProfiles.profile === PowerProfile.Performance ? Theme.red : Theme.green
                    // Tap cycles Saver → Balanced → Performance.
                    onToggled: {
                        const i = view.profiles.findIndex(p => p.id === PowerProfiles.profile);
                        PowerProfiles.profile = view.profiles[(i + 1) % 3].id;
                    }
                }
            }

            // ── Wi‑Fi networks (from the tile's chevron) ─────────────────
            Item {
                width: parent.width
                height: view.wifiOpen ? wifiList.implicitHeight : 0
                visible: height > 0.5
                clip: true
                Behavior on height { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.reflowMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                WifiList {
                    id: wifiList
                    center: view.center
                    device: view.wifiDevice
                    open: view.wifiOpen && view.shown
                    opacity: view.wifiOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                }
            }

            // ── Battery ──────────────────────────────────────────────────
            Rectangle {
                visible: view.hasBattery
                width: parent.width
                height: 52
                radius: 16
                color: Qt.rgba(1, 1, 1, 0.065)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)
                opacity: view.center.revealAt(100)
                readonly property int level: view.hasBattery ? view.pct(view.battery.percentage) : 0
                readonly property bool charging: view.hasBattery && (view.battery.state === UPowerDeviceState.Charging || view.battery.state === UPowerDeviceState.FullyCharged)

                // Battery glyph drawn as a capsule that fills
                Item {
                    id: cell
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 16
                    Rectangle {
                        anchors.fill: parent
                        radius: 5
                        color: "transparent"
                        border.width: 1.5
                        border.color: Qt.rgba(1, 1, 1, 0.5)
                    }
                    Rectangle {
                        x: 3; y: 3
                        height: parent.height - 6
                        width: Math.max(2, (parent.width - 6) * parent.parent.level / 100)
                        radius: 2.5
                        color: parent.parent.charging ? Theme.green : parent.parent.level <= 20 ? Theme.red : Theme.textPrimary
                    }
                    Rectangle { x: parent.width + 1; anchors.verticalCenter: parent.verticalCenter; width: 2; height: 6; radius: 1; color: Qt.rgba(1, 1, 1, 0.5) }
                }
                Column {
                    anchors { left: cell.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 1
                    RollingNumber {
                        value: parent.parent.level
                        suffix: "%"
                        size: 14
                        weight: Theme.wSemibold
                    }
                    Label {
                        text: {
                            const b = view.battery;
                            if (!view.hasBattery) return "";
                            if (b.state === UPowerDeviceState.FullyCharged) return "Fully charged";
                            if (b.state === UPowerDeviceState.Charging) return "Charging" + (b.timeToFull > 0 ? " · full in " + view.duration(b.timeToFull) : "");
                            // Plugged in but not charging: held at a charge limit
                            // (pending-charge) or just topping off. Not "on battery".
                            if (!UPower.onBattery) return b.state === UPowerDeviceState.PendingCharge ? "Plugged in · holding charge" : "Plugged in";
                            return b.timeToEmpty > 0 ? view.duration(b.timeToEmpty) + " left" : "On battery";
                        }
                        size: 12
                        color: Theme.textTertiary
                    }
                }
                Label {
                    visible: view.profilesAvailable
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: view.profileLabel
                    size: 12
                    weight: Theme.wMedium
                    color: Theme.textSecondary
                }
            }

            // ── Brightness ───────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: 8
                opacity: view.center.revealAt(140)

                Label { x: 4; text: "Brightness"; size: 14; weight: Theme.wSemibold; color: Theme.textSecondary }
                Repeater {
                    model: Display.outputs
                    Column {
                        id: out
                        required property var modelData
                        width: column.width
                        spacing: 4
                        Slider {
                            width: parent.width
                            from: 0; to: 100; stepSize: 1
                            value: out.modelData.value
                            glyph: out.modelData.internal ? "\u{f0322}" : "\u{f0379}"     // laptop / monitor
                            label: out.modelData.internal ? "Built-in Display" : (view.modelOf(out.modelData.name) || out.modelData.name)
                            valueText: Math.round(out.modelData.value) + "%"
                            fillColor: Qt.rgba(1, 1, 1, 0.42)   // white you can see, like the Warmth fill's weight
                            onMoved: v => Display.setBrightness(out.modelData.name, v)
                        }
                        Label {
                            visible: out.modelData.error !== ""
                            x: 4
                            width: parent.width - 8
                            elide: Text.ElideRight
                            text: out.modelData.error
                            size: 11
                            color: Theme.caution
                        }
                    }
                }
                Label {
                    visible: Display.outputs.length === 0
                    x: 4
                    text: "Reading displays…"
                    size: 12
                    color: Theme.textTertiary
                }
                Slider {
                    width: parent.width
                    // Warmer to the right; 6500K is neutral (Night Shift off).
                    from: 6500; to: 2500; stepSize: 100
                    value: Display.temperature
                    glyph: "\u{f0599}"
                    label: "Warmth"
                    valueText: Display.nightOn ? Display.temperature + " K" : "Off"
                    fillColor: Qt.alpha(Theme.orange, 0.28 + 0.4 * Math.max(0, (6500 - Display.temperature) / 4000))
                    onMoved: v => Display.setTemperature(v)
                }
            }

            // ── Bluetooth devices ────────────────────────────────────────
            Column {
                visible: view.adapter && view.adapter.enabled && view.btDevices.length > 0
                width: parent.width
                spacing: 8
                opacity: view.center.revealAt(180)

                Label { x: 4; text: "Devices"; size: 14; weight: Theme.wSemibold; color: Theme.textSecondary }
                Repeater {
                    model: view.btDevices
                    Rectangle {
                        id: dev
                        required property var modelData
                        readonly property bool busy: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
                        width: column.width
                        height: 48
                        radius: 16
                        color: devArea.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.065)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)
                        scale: devArea.pressed ? 0.985 : 1
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

                        Rectangle {
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 30; radius: 15
                            color: dev.modelData.connected ? Theme.blue : Theme.platter
                            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                            Text {
                                anchors.centerIn: parent
                                text: /headset|headphone|audio/.test(dev.modelData.icon) ? "\u{f02cb}"
                                    : /phone/.test(dev.modelData.icon) ? "\u{f011c}"
                                    : /mouse/.test(dev.modelData.icon) ? "\u{f037d}"
                                    : /keyboard/.test(dev.modelData.icon) ? "\u{f030c}" : "\u{f00af}"
                                font.family: Theme.fontGlyph
                                font.pixelSize: 15
                                color: Theme.textPrimary
                            }
                        }
                        Column {
                            x: 52
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 52 - 70
                            spacing: 1
                            Label { width: parent.width; elide: Text.ElideRight; text: dev.modelData.name; size: 13; weight: Theme.wSemibold }
                            Label {
                                text: dev.busy ? (dev.modelData.connected ? "Disconnecting…" : "Connecting…")
                                    : dev.modelData.connected ? "Connected" : "Not connected"
                                size: 11
                                color: Theme.textTertiary
                            }
                        }
                        Label {
                            visible: dev.modelData.batteryAvailable
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            text: Math.round(dev.modelData.battery * 100) + "%"
                            size: 12
                            rounded: true
                            weight: Theme.wMedium
                            font.features: ({ "tnum": 1 })
                            color: dev.modelData.battery < 0.2 ? Theme.red : Theme.textSecondary
                        }
                        MouseArea {
                            id: devArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dev.modelData.connected ? dev.modelData.disconnect() : dev.modelData.connect()
                        }
                    }
                }
            }
        }
    }

    // A Control Center tile (components/ui/ControlTile), two to a row here.
    component Tile: ControlTile {
        id: t
        width: (view.width - 8) / 2
        onTip: (shown, text) => view.center.tip(t, shown, text)
    }
}
