// What the lock screen shows: the wallpaper (blurred once, drifting
// slowly; still under reduced motion), the date, a big rounded clock whose
// digits roll, then your picture, your name and the password pill. A wrong
// password shakes the pill (a damped spring, Apple's "no").
//
// `lock` carries the state (Lock.qml); `preview` draws it without a session
// lock, for the off-screen test.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components

Item {
    id: view
    required property var lock
    property bool preview: false

    readonly property string home: Quickshell.env("HOME")
    readonly property string user: { const u = Quickshell.env("USER") || ""; return u.charAt(0).toUpperCase() + u.slice(1); }
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: view.now = new Date() }

    // ── Background ───────────────────────────────────────────────────────
    Item {
        id: drift
        anchors.fill: parent
        scale: 1.08
        // The wallpaper, decoded small and blurred once: the layer caches the
        // result, so the drift below only moves a texture.
        Item {
            anchors.fill: parent
            layer.enabled: true
            Image {
                id: wall
                anchors.fill: parent
                source: "file://" + view.home + "/.cache/hyde/wall.set"
                sourceSize: Qt.size(640, 360)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: wall
                blurEnabled: true
                blur: 1
                blurMax: 40
                saturation: 0.15
                brightness: -0.04
            }
        }
        // One slow loop (90 s): enough to feel alive, too slow to notice moving.
        SequentialAnimation on x {
            running: !Theme.reduceMotion
            loops: Animation.Infinite
            NumberAnimation { from: -30; to: 30; duration: 45000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 30; to: -30; duration: 45000; easing.type: Easing.InOutSine }
        }
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.28) }

    // ── Date and time ────────────────────────────────────────────────────
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.12)
        spacing: 0
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(view.now, "dddd, d MMMM")
            size: 24
            weight: Theme.wSemibold
            color: Qt.rgba(1, 1, 1, 0.85)
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            RollingNumber { value: view.now.getHours(); pad: 2; size: 132; weight: Theme.wSemibold; color: Qt.rgba(1, 1, 1, 0.92) }
            Label { text: ":"; size: 132; weight: Theme.wSemibold; rounded: true; color: Qt.rgba(1, 1, 1, 0.92) }
            RollingNumber { value: view.now.getMinutes(); pad: 2; size: 132; weight: Theme.wSemibold; color: Qt.rgba(1, 1, 1, 0.92) }
        }
    }

    // ── Who, and the password ────────────────────────────────────────────
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(parent.height * 0.12)
        spacing: 14

        ClippingRectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72; height: 72; radius: 36
            color: Qt.rgba(1, 1, 1, 0.18)
            Image {
                id: face
                anchors.fill: parent
                source: "file://" + view.home + "/.face"
                sourceSize: Qt.size(144, 144)
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
            }
            Label { visible: face.status !== Image.Ready; anchors.centerIn: parent; text: view.user.charAt(0); size: 30; weight: Theme.wSemibold }
        }
        Label { anchors.horizontalCenter: parent.horizontalCenter; text: view.user; size: 17; weight: Theme.wSemibold }

        Item {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260; height: 40
            // The shake: a damped spring kicked sideways on every miss.
            Spring { id: shake; tier: ({ stiffness: 900, damping: 9 }); target: 0 }
            Connections { target: view.lock; function onFailuresChanged() { if (Theme.reduceMotion) return; shake.velocity = 900; shake.settled = false; } }
            transform: Translate { x: shake.value }

            Rectangle {
                anchors.fill: parent
                radius: 20
                color: Qt.rgba(1, 1, 1, 0.16)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, view.lock.error ? 0 : 0.14)
            }
            TextInput {
                id: field
                anchors { left: parent.left; leftMargin: 18; right: go.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                focus: !view.preview
                enabled: !view.lock.checking
                echoMode: TextInput.Password
                passwordCharacter: "●"
                passwordMaskDelay: 0
                text: view.lock.password
                onTextChanged: if (text !== view.lock.password) view.lock.password = text
                color: "white"
                font.pixelSize: 14
                font.letterSpacing: 2
                horizontalAlignment: TextInput.AlignHCenter
                Keys.onReturnPressed: view.lock.submit()
                Keys.onEnterPressed: view.lock.submit()
                Keys.onEscapePressed: view.lock.password = ""
                Label {
                    visible: !field.text
                    anchors.centerIn: parent
                    text: view.lock.checking ? "Checking…" : "Enter Password"
                    size: 14
                    color: Qt.rgba(1, 1, 1, 0.6)
                }
            }
            Rectangle {
                id: go
                anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
                width: 30; height: 30; radius: 15
                color: Qt.rgba(1, 1, 1, view.lock.password ? 0.3 : 0.12)
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                Text { anchors.centerIn: parent; text: "\u{f0054}"; font.family: Theme.fontGlyph; font.pixelSize: 16; color: "white" }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.lock.submit() }
            }
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.lock.error || "Type your password, then ↵"
            size: 12
            color: view.lock.error ? "#ff6961" : Qt.rgba(1, 1, 1, 0.6)
        }
    }
}
