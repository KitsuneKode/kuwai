// The power menu, grown out of the island (Super+Escape). Lock and Sleep act
// at once; Log Out, Restart and Shut Down are held: a ring fills while you
// hold (0.9 s, linear: the deliberate part), and lets go quickly if you stop
// (200 ms ease-out). Keys: ←→ choose, hold ↵ (or Space), Esc closes.
//
//   ( 🔒 )   ( ☾ )   ( ⇥ )   ( ↻ )   ( ⏻ )
//    Lock    Sleep  Log Out Restart Shut Down
//                 hold to restart · up 3h 12m
//
// RICE_DRYRUN=1 logs the command instead of running it (the off-screen test).
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

FocusScope {
    id: power
    focus: true

    readonly property var actions: [
        { id: "lock", label: "Lock", glyph: "\u{f033e}", hold: false, cmd: ["loginctl", "lock-session"] },
        { id: "sleep", label: "Sleep", glyph: "\u{f04b2}", hold: false, cmd: ["systemctl", "suspend"] },
        { id: "logout", label: "Log Out", glyph: "\u{f0343}", hold: true, cmd: ["hyprctl", "dispatch", "exit"] },
        { id: "reboot", label: "Restart", glyph: "\u{f0709}", hold: true, cmd: ["systemctl", "reboot"] },
        { id: "off", label: "Shut Down", glyph: "\u{f0425}", hold: true, cmd: ["systemctl", "poweroff"] }
    ]
    property int current: 0
    property int holding: -1
    property real held: 0                 // 0–1 of the current hold
    property string uptime: ""

    implicitWidth: row.implicitWidth + 56
    implicitHeight: 184

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
        else if (k >= Qt.Key_1 && k <= Qt.Key_5) { current = k - Qt.Key_1; }
        else return;
        event.accepted = true;
    }
    Keys.onReleased: event => {
        if (event.isAutoRepeat) return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) letGo();
    }

    FileView {
        id: up
        path: "/proc/uptime"
        onLoaded: {
            const s = Math.floor(parseFloat(text()));
            const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
            power.uptime = "up " + (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
        }
    }

    Row {
        id: row
        anchors.horizontalCenter: parent.horizontalCenter
        y: 26
        spacing: 14
        Repeater {
            model: power.actions
            Column {
                id: act
                required property var modelData
                required property int index
                readonly property bool on: power.current === index
                readonly property bool danger: modelData.id === "off" || modelData.id === "reboot"
                spacing: 9
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64; height: 64
                    scale: actArea.pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Rectangle {
                        anchors.fill: parent
                        radius: 32
                        color: act.on ? (act.danger && power.holding === act.index ? Qt.alpha(Theme.red, 0.35) : Qt.rgba(1, 1, 1, 0.20))
                             : actArea.containsMouse ? Theme.pillHover : Theme.pill
                        border.width: act.on ? 1 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.35)
                        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: act.modelData.glyph
                        font.family: Theme.fontGlyph
                        font.pixelSize: 24
                        color: Theme.textPrimary
                    }
                    // The hold ring.
                    Canvas {
                        id: ring
                        anchors.fill: parent
                        visible: act.modelData.hold && power.held > 0 && power.current === act.index
                        readonly property real p: power.held
                        onPChanged: requestPaint()
                        onPaint: {
                            const c = getContext("2d");
                            c.reset();
                            c.lineWidth = 3;
                            c.lineCap = "round";
                            c.strokeStyle = act.danger ? "#ff453a" : "white";
                            c.beginPath();
                            c.arc(width / 2, height / 2, width / 2 - 2, -Math.PI / 2, -Math.PI / 2 + p * Math.PI * 2);
                            c.stroke();
                        }
                    }
                    MouseArea {
                        id: actArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: power.current = act.index
                        onPressed: power.press(act.index)
                        onReleased: power.letGo()
                        onCanceled: power.letGo()
                    }
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: act.modelData.label
                    size: 12
                    weight: act.on ? Theme.wMedium : Theme.wRegular
                    color: act.on ? Theme.textPrimary : Theme.textSecondary
                }
            }
        }
    }

    Label {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 20 }
        readonly property var a: power.actions[power.current]
        text: (a.hold ? "Hold to " + a.label.toLowerCase() : "Click or press ↵") + (power.uptime ? "  ·  " + power.uptime : "")
        size: 12
        color: Theme.textTertiary
    }
}
