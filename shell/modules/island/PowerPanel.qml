// The power menu, grown out of the island (Super+Backspace). Who you are and
// how long the machine has been up on top, then large tiles. Lock and Sleep
// act at once; Log Out, Restart, Firmware (restart into the UEFI setup) and
// Shut Down are held: a wash of colour fills the tile while you hold (0.9 s,
// linear: the deliberate part) and drains quickly if you let go (200 ms).
//
//   (◉) Kitsunekode                         up 1d 11h · 87% ⚡
//   ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
//   │  🔒  │ │  ☾   │ │  ⇥   │ │  ↻   │ │  ⌁   │ │  ⏻   │
//   │ Lock │ │Sleep │ │LogOut│ │Restrt│ │Firmw.│ │ShutDn│
//   └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘
//                         Hold ↵ to restart
//
// Keys: ←→ (or 1–6) choose, ↵ / Space (held for the held ones), Esc.
// RICE_DRYRUN=1 logs the command instead of running it (the off-screen test).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.UPower
import qs.config
import qs.components
import qs.services

FocusScope {
    id: power
    focus: true

    readonly property var actions: [
        { id: "lock", label: "Lock", glyph: "\u{f033e}", hold: false, cmd: ["loginctl", "lock-session"] },     // hyprlock until the rice lock is the default
        { id: "sleep", label: "Sleep", glyph: "\u{f0594}", hold: false, cmd: ["systemctl", "suspend"] },
        { id: "logout", label: "Log Out", glyph: "\u{f0343}", hold: true, cmd: ["hyprctl", "dispatch", "exit"] },
        { id: "reboot", label: "Restart", glyph: "\u{f0709}", hold: true, cmd: ["systemctl", "reboot"] },
        { id: "firmware", label: "Firmware", glyph: "\u{f061a}", hold: true, cmd: ["systemctl", "reboot", "--firmware-setup"] },
        { id: "off", label: "Shut Down", glyph: "\u{f0425}", hold: true, danger: true, cmd: ["systemctl", "poweroff"] }
    ]
    property int current: 0
    property int holding: -1
    property real held: 0                 // 0–1 of the current hold
    property string uptime: ""
    readonly property string user: { const u = Quickshell.env("USER") || ""; return u.charAt(0).toUpperCase() + u.slice(1); }
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery && battery.isLaptopBattery && battery.isPresent
    readonly property int pct: hasBattery ? Math.round(battery.percentage > 1 ? battery.percentage : battery.percentage * 100) : 0
    readonly property bool charging: hasBattery && battery.state === UPowerDeviceState.Charging

    implicitWidth: 620
    implicitHeight: 236

    function run(i) {
        const a = actions[i];
        Island.close();
        if (Quickshell.env("RICE_DRYRUN") === "1") { console.warn("power (dry run): " + a.cmd.join(" ")); return; }
        // Let the island fold away first, so a lock screen doesn't catch it half-open.
        launch.command = a.cmd;
        later.restart();
    }
    Process { id: launch }
    Timer { id: later; interval: 220; onTriggered: launch.running = true }

    function press(i) {
        current = i;
        if (!actions[i].hold) { run(i); return; }
        holding = i;
        release.stop();
        fill.from = held;
        fill.duration = Math.round(900 * (1 - held));
        fill.restart();
    }
    function letGo() {
        if (holding < 0) return;
        fill.stop();
        holding = -1;
        if (held < 1) release.restart();
    }
    NumberAnimation {
        id: fill
        target: power; property: "held"; to: 1
        onFinished: if (power.holding >= 0 && power.held >= 1) { const i = power.holding; power.holding = -1; power.run(i); }
    }
    NumberAnimation { id: release; target: power; property: "held"; to: 0; duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }

    Keys.onPressed: event => {
        const k = event.key;
        if (event.isAutoRepeat) { event.accepted = true; return; }
        if (k === Qt.Key_Left) current = (current + actions.length - 1) % actions.length;
        else if (k === Qt.Key_Right || k === Qt.Key_Tab) current = (current + 1) % actions.length;
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) press(current);
        else if (k >= Qt.Key_1 && k <= Qt.Key_6) current = k - Qt.Key_1;
        else return;
        event.accepted = true;
    }
    Keys.onReleased: event => {
        if (event.isAutoRepeat) return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) letGo();
    }

    FileView {
        path: "/proc/uptime"
        onLoaded: {
            const s = Math.floor(parseFloat(text()));
            const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
            power.uptime = "up " + (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
        }
    }

    // ── Who ──────────────────────────────────────────────────────────────
    Item {
        x: 24; y: 20
        width: parent.width - 48; height: 40
        ClippingRectangle {
            id: face
            width: 40; height: 40; radius: 20
            color: Theme.pill
            Image { id: faceImg; anchors.fill: parent; source: "file://" + Quickshell.env("HOME") + "/.face"; sourceSize: Qt.size(80, 80); fillMode: Image.PreserveAspectCrop; asynchronous: true }
            Label { visible: faceImg.status !== Image.Ready; anchors.centerIn: parent; text: power.user.charAt(0); size: 18; weight: Theme.wSemibold }
        }
        Column {
            anchors { left: face.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
            Label { text: power.user; size: 15; weight: Theme.wSemibold }
            Label { text: power.uptime + (power.hasBattery ? "  ·  " + power.pct + "%" + (power.charging ? " charging" : "") : ""); size: 12; color: Theme.textTertiary }
        }
    }

    // ── Tiles ────────────────────────────────────────────────────────────
    Row {
        id: row
        anchors.horizontalCenter: parent.horizontalCenter
        y: 80
        spacing: 10
        Repeater {
            model: power.actions
            Item {
                id: tile
                required property var modelData
                required property int index
                readonly property bool on: power.current === index
                readonly property color wash: modelData.danger || modelData.id === "reboot" || modelData.id === "firmware" ? Theme.red : Theme.accent
                width: 88; height: 96
                scale: area.pressed && !modelData.hold ? 0.95 : 1
                Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: 22
                    color: tile.on ? Qt.rgba(1, 1, 1, 0.16) : area.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.06)
                    border.width: tile.on ? 1 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.22)
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                    // The hold: a wash of colour from the left.
                    Rectangle {
                        visible: tile.modelData.hold && power.current === tile.index && power.held > 0
                        width: parent.width * power.held
                        height: parent.height
                        color: Qt.alpha(tile.wash, 0.55)
                    }
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.modelData.glyph
                        font.family: Theme.fontGlyph
                        font.pixelSize: 28
                        color: tile.modelData.danger && tile.on ? Theme.red : Theme.textPrimary
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.modelData.label
                        size: 12
                        weight: tile.on ? Theme.wMedium : Theme.wRegular
                        color: tile.on ? Theme.textPrimary : Theme.textSecondary
                    }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: power.current = tile.index
                    onPressed: power.press(tile.index)
                    onReleased: power.letGo()
                    onCanceled: power.letGo()
                }
            }
        }
    }

    Label {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
        readonly property var a: power.actions[power.current]
        text: a.hold ? "Hold to " + (a.id === "firmware" ? "restart into the firmware setup" : a.label.toLowerCase()) : a.id === "lock" ? "Click or press ↵ to lock" : "Click or press ↵ to sleep"
        size: 12
        color: power.holding >= 0 ? Theme.textPrimary : Theme.textTertiary
    }
}
