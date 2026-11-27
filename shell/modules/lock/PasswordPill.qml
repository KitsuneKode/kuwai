// The password pill and the line under it, shared by the lock screen
// (LockView) and the login screen (GreeterView). No echo: a dot per
// character shows anyone watching the length, so five dots pulse once per
// keystroke instead. A wrong password shakes the pill (a damped spring:
// Apple's "no") and keeps the keyboard.
//
// Caps Lock on shows under the pill (asked of Hyprland after each key, so
// the key that turned it on is the one that shows it). The arrow fills with
// the accent once there's something to send.
//
// `lock` carries the state: password, checking, error, failures, submit().
import QtQuick
import Quickshell.Io
import qs.config
import qs.components

Column {
    id: entry
    required property var lock
    property bool preview: false
    property string placeholder: entry.lock && entry.lock.challenge ? entry.lock.challenge : "Enter Password"
    property color accent: Theme.accent
    readonly property color onAccent: (0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b) > 0.55 ? Theme.inkOnLight : "white"
    property bool capsLock: false
    Process {
        id: caps
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { entry.capsLock = JSON.parse(text).keyboards.some(k => k.capsLock); } catch (e) {}
            }
        }
    }
    Timer { id: capsAsk; interval: 60; onTriggered: if (!caps.running) caps.running = true }
    Component.onCompleted: if (!preview) caps.running = true
    // Any key in the field: the view keeps the pill up while you type.
    signal activity()
    function reclaim() {
        const w = field.Window.window;
        const f = w ? w.activeFocusItem : null;
        if (!f || f === w.contentItem) field.forceActiveFocus();
    }
    signal dismissed()
    function focusField() { if (!preview) field.forceActiveFocus(); }
    readonly property bool fieldFocused: field.activeFocus
    // A key typed while a control held the keyboard (Tab took it to a power
    // button, a track button, a card): the field takes the keyboard back and
    // the character with it, so a password started anywhere still lands.
    function typeKey(t) {
        if (preview || field.readOnly) return;
        field.forceActiveFocus();
        field.insert(field.cursorPosition, t);
    }
    // The views' shared key path for their controls: Esc puts the keyboard
    // back in the field, a printable key types there. True when it took the key.
    function routeKey(e) {
        if (preview || field.activeFocus) return false;
        if (e.key === Qt.Key_Escape) { focusField(); return true; }
        const plain = !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
        if (plain && e.text.length === 1 && e.text >= " " && e.text !== "\u007f") { typeKey(e.text); return true; }
        return false;
    }

    spacing: 10

    Item {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        width: Theme.sp(270); height: Theme.sp(42)
        Spring { id: shake; tier: ({ stiffness: 900, damping: 9 }); target: 0 }
        Connections { target: entry.lock; function onFailuresChanged() { if (Theme.reduceMotion) return; shake.velocity = 900; shake.settled = false; } }
        transform: Translate { x: shake.value }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.wash(3)
            border.width: 1
            border.color: entry.lock.error ? Qt.alpha(Theme.red, 0.6) : Theme.edge(2)
        }
        TextInput {
            id: field
            anchors { left: parent.left; leftMargin: 18; right: go.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            focus: !entry.preview
            // Never disabled (a disabled field drops the keyboard): read-only while PAM checks.
            readOnly: entry.lock.checking
            echoMode: TextInput.NoEcho
            // A password field to assistive tech: named by its prompt, never by what's typed.
            Accessible.role: Accessible.EditableText
            Accessible.passwordEdit: true
            Accessible.name: entry.placeholder
            Accessible.description: entry.lock.checking ? "Checking" : entry.lock.error || (entry.capsLock ? "Caps Lock is on" : "")
            onTextChanged: { if (text !== entry.lock.password) entry.lock.password = text; if (text.length && !Theme.reduceMotion) for (const w of lockDots.waves) w.restart(); }
            Row {
                id: lockDots
                property var waves: []
                visible: field.text.length > 0 || entry.lock.password.length > 0
                anchors.centerIn: parent
                spacing: 7
                Repeater {
                    model: 5
                    Rectangle {
                        id: ld
                        required property int index
                        width: 8; height: 8; radius: 4
                        color: "white"; opacity: 0.6
                        SequentialAnimation {
                            id: ldWave
                            PauseAnimation { duration: ld.index * 28 }
                            ParallelAnimation {
                                NumberAnimation { target: ld; property: "opacity"; to: 1; duration: Theme.kickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                                NumberAnimation { target: ld; property: "scale"; to: 1.25; duration: Theme.kickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                            }
                            ParallelAnimation {
                                NumberAnimation { target: ld; property: "opacity"; to: 0.6; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                                NumberAnimation { target: ld; property: "scale"; to: 1; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                            }
                        }
                        Component.onCompleted: lockDots.waves = [...lockDots.waves, ldWave]
                    }
                }
            }
            // Typing breaks a `text:` binding: follow the shared password (a miss clears every screen).
            Connections {
                target: entry.lock
                function onPasswordChanged() { if (field.text !== entry.lock.password) field.text = entry.lock.password; }
                function onFailuresChanged() { entry.focusField(); }
            }
            // Losing the keyboard to nothing (a click on bare ground, the window
            // coming back) takes it back; losing it to a control Tab reached
            // keeps it there: Esc or any typed key returns (routeKey).
            activeFocusOnTab: !entry.preview
            onActiveFocusChanged: if (!activeFocus && !entry.preview) Qt.callLater(entry.reclaim)
            color: "white"
            font.pixelSize: Theme.sp(14)
            font.letterSpacing: 2
            horizontalAlignment: TextInput.AlignHCenter
            Keys.onReturnPressed: entry.lock.submit()
            Keys.onEnterPressed: entry.lock.submit()
            Keys.onEscapePressed: { entry.lock.password = ""; entry.dismissed(); }
            Keys.onPressed: event => { entry.activity(); capsAsk.restart(); event.accepted = false; }
            Label { visible: !field.text && !entry.lock.password; anchors.centerIn: parent; text: entry.placeholder; size: Theme.tCallout; color: Qt.rgba(1, 1, 1, 0.6) }
        }
        Rectangle {
            id: go
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            width: Theme.sp(30); height: width; radius: width / 2
            color: entry.lock.password ? Qt.alpha(entry.accent, 0.9) : Theme.wash(2)
            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
            scale: goPress.pressed ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: entry.lock.checking ? "\u{f0772}" : "\u{f0054}"
                font.family: Theme.fontGlyph; font.pixelSize: Theme.sp(Theme.glyphS)
                color: entry.lock.password ? entry.onAccent : "white"
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                RotationAnimation on rotation { running: entry.lock.checking && !Theme.reduceMotion; loops: Animation.Infinite; from: 0; to: 360; duration: Theme.spinMs }
                onTextChanged: rotation = 0
            }
            MouseArea { id: goPress; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: entry.lock.submit() }
            Accessible.role: Accessible.Button
            Accessible.name: entry.lock.checking ? "Checking" : "Submit password"
            Accessible.onPressAction: entry.lock.submit()
        }
    }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, Theme.sp(Theme.lockPillW))
        elide: Text.ElideRight
        text: entry.lock.checking ? (entry.lock.note || "Checking…") : entry.lock.error || (entry.capsLock ? "Caps Lock is on" : entry.lock.fingerReady ? "Or touch the fingerprint sensor" : " ")
        size: Theme.tSub; weight: entry.lock.error ? Theme.wMedium : Theme.wRegular
        color: entry.lock.error ? Theme.redText : Qt.rgba(1, 1, 1, 0.7)
    }
}
