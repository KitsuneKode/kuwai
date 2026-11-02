// What the lock screen shows (after the reference): the island at the top
// with a lock in it, the date over a big rounded clock in the theme's tint,
// a line of glanceable things (weather, battery, focus), what's playing on a
// glass card, and "Press any key to unlock" at the bottom. A key or a click
// turns that line into the password pill (it rises out of the hint on a
// spring); left empty for 12 s it settles back. The wallpaper is blurred
// once and drifts slowly (still under reduced motion). A wrong password
// shakes the pill (a damped spring: Apple's "no") and keeps the keyboard.
//
// `lock` carries the state (Lock.qml); `preview` draws it without a session
// lock, for the off-screen test.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.UPower
import qs.config
import qs.components
import qs.services
import qs.modules.island

Item {
    id: view
    required property var lock
    property bool preview: false

    readonly property string home: Quickshell.env("HOME")
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: view.now = new Date() }
    // The clock's tint: the theme's accent, lifted towards white so it reads on any wallpaper.
    readonly property color tint: Qt.tint(Qt.rgba(1, 1, 1, 0.9), Qt.alpha(Theme.accent, 0.35))

    // Asking for the password, or just showing the time.
    property bool asking: false
    function ask() { asking = true; settle.restart(); if (!preview) field.forceActiveFocus(); }
    Timer { id: settle; interval: 12000; onTriggered: if (view.lock.password === "" && !view.lock.checking) view.asking = false }
    Connections { target: view.lock; function onPasswordChanged() { if (view.lock.password !== "") { view.asking = true; settle.restart(); } } }

    // ── Background ───────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        scale: 1.08
        // The wallpaper, decoded small and blurred once: the layer caches the
        // result, so the drift only moves a texture.
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
            MultiEffect { anchors.fill: parent; source: wall; blurEnabled: true; blur: 1; blurMax: 48; saturation: 0.25 }
        }
        SequentialAnimation on x {
            running: !Theme.reduceMotion
            loops: Animation.Infinite
            NumberAnimation { from: -30; to: 30; duration: 45000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 30; to: -30; duration: 45000; easing.type: Easing.InOutSine }
        }
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.22) }

    // ── The island, locked ───────────────────────────────────────────────
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Settings.islandStyle === "notch" ? -20 : 6
        width: 150; height: Settings.islandStyle === "notch" ? 54 : 34
        radius: 17
        color: "black"
        Text {
            anchors { left: parent.left; leftMargin: 18; bottom: parent.bottom; bottomMargin: 9 }
            text: "\u{f033e}"
            font.family: Theme.fontGlyph
            font.pixelSize: 14
            color: Qt.rgba(1, 1, 1, 0.9)
        }
        IslandStatus {
            anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 10 }
            tint: Qt.rgba(1, 1, 1, 0.9)
        }
    }

    // ── Date, time, glance ───────────────────────────────────────────────
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.11)
        spacing: 4
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(view.now, "ddd, MMM d")
            size: 26; weight: Theme.wSemibold
            color: view.tint
        }
        TextMorph {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Settings.clock24 ? Qt.formatTime(view.now, "HH:mm") : Qt.formatTime(view.now, "h:mm")
            size: 150; weight: Theme.wBold; rounded: true
            color: view.tint
            duration: 700; stagger: 60
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 22
            spacing: 24
            Row {
                visible: SystemStats.weatherTemp !== ""
                spacing: 7
                Text { anchors.verticalCenter: parent.verticalCenter; text: SystemStats.weatherGlyph; font.family: Theme.fontGlyph; font.pixelSize: 18; color: view.tint }
                Label { anchors.verticalCenter: parent.verticalCenter; text: SystemStats.weatherTemp; size: 18; weight: Theme.wMedium; color: view.tint }
            }
            Row {
                readonly property var b: UPower.displayDevice
                visible: b && b.isLaptopBattery && b.isPresent
                spacing: 7
                Text { anchors.verticalCenter: parent.verticalCenter; text: UPower.onBattery ? "\u{f0079}" : "\u{f06a5}"; font.family: Theme.fontGlyph; font.pixelSize: 18; color: view.tint }
                Label { anchors.verticalCenter: parent.verticalCenter; text: parent.b ? Math.round(parent.b.percentage > 1 ? parent.b.percentage : parent.b.percentage * 100) + "%" : ""; size: 18; weight: Theme.wMedium; color: view.tint }
            }
            Row {
                visible: Notifs.dnd
                spacing: 7
                Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0594}"; font.family: Theme.fontGlyph; font.pixelSize: 18; color: view.tint }
                Label { anchors.verticalCenter: parent.verticalCenter; text: "Focus"; size: 18; weight: Theme.wMedium; color: view.tint }
            }
        }
    }

    // ── Now playing ──────────────────────────────────────────────────────
    LockMedia {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.50)
    }

    // ── Unlock ───────────────────────────────────────────────────────────
    Spring { id: ask; tier: ({ stiffness: 300, damping: 24 }); target: view.asking || view.lock.checking || view.lock.error !== "" ? 1 : 0 }
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(parent.height * 0.08)
        width: 300; height: 76

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            opacity: Math.max(0, 1 - ask.value * 2)
            visible: opacity > 0.01
            text: "Press any key to unlock"
            size: 17; weight: Theme.wMedium
            color: Qt.alpha(view.tint, 0.85)
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            spacing: 10
            opacity: Math.max(0, Math.min(1, (ask.value - 0.3) / 0.6))
            transform: Translate { y: (1 - Math.min(1, ask.value)) * 14 }

            Item {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                width: 270; height: 42
                Spring { id: shake; tier: ({ stiffness: 900, damping: 9 }); target: 0 }
                Connections { target: view.lock; function onFailuresChanged() { if (Theme.reduceMotion) return; shake.velocity = 900; shake.settled = false; } }
                transform: Translate { x: shake.value }
                Rectangle {
                    anchors.fill: parent
                    radius: 21
                    color: Qt.rgba(1, 1, 1, 0.16)
                    border.width: 1
                    border.color: view.lock.error ? Qt.alpha(Theme.red, 0.6) : Qt.rgba(1, 1, 1, 0.18)
                }
                TextInput {
                    id: field
                    anchors { left: parent.left; leftMargin: 18; right: go.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    focus: !view.preview
                    // Never disabled (a disabled field drops the keyboard): read-only while PAM checks.
                    readOnly: view.lock.checking
                    // No echo (a dot per character shows anyone watching
                    // the length); five dots pulse once per keystroke instead.
                    echoMode: TextInput.NoEcho
                    onTextChanged: { if (text !== view.lock.password) view.lock.password = text; if (text.length && !Theme.reduceMotion) for (const w of lockDots.waves) w.restart(); }
                    Row {
                        id: lockDots
                        property var waves: []
                        visible: field.text.length > 0
                        anchors.verticalCenter: parent.verticalCenter
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
                                        NumberAnimation { target: ld; property: "opacity"; to: 1; duration: 90; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: ld; property: "scale"; to: 1.25; duration: 90; easing.type: Easing.OutQuad }
                                    }
                                    ParallelAnimation {
                                        NumberAnimation { target: ld; property: "opacity"; to: 0.6; duration: 220; easing.type: Easing.OutCubic }
                                        NumberAnimation { target: ld; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                                    }
                                }
                                Component.onCompleted: lockDots.waves = [...lockDots.waves, ldWave]
                            }
                        }
                    }
                    // Typing breaks a `text:` binding: follow the shared password (a miss clears every screen).
                    Connections {
                        target: view.lock
                        function onPasswordChanged() { if (field.text !== view.lock.password) field.text = view.lock.password; }
                        function onFailuresChanged() { if (!view.preview) field.forceActiveFocus(); }
                    }
                    onActiveFocusChanged: if (!activeFocus && !view.preview) Qt.callLater(() => field.forceActiveFocus())
                    color: "white"
                    font.pixelSize: 14
                    font.letterSpacing: 2
                    horizontalAlignment: TextInput.AlignHCenter
                    Keys.onReturnPressed: view.lock.submit()
                    Keys.onEnterPressed: view.lock.submit()
                    Keys.onEscapePressed: { view.lock.password = ""; view.asking = false; }
                    Keys.onPressed: event => { view.ask(); event.accepted = false; }
                    Label { visible: !field.text; anchors.centerIn: parent; text: "Enter Password"; size: 14; color: Qt.rgba(1, 1, 1, 0.6) }
                }
                Rectangle {
                    id: go
                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 30; height: 30; radius: 15
                    color: Qt.rgba(1, 1, 1, view.lock.password ? 0.3 : 0.12)
                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                    Text {
                        anchors.centerIn: parent
                        text: view.lock.checking ? "\u{f0772}" : "\u{f0054}"
                        font.family: Theme.fontGlyph; font.pixelSize: 16; color: "white"
                        RotationAnimation on rotation { running: view.lock.checking && !Theme.reduceMotion; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                        onTextChanged: rotation = 0
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.lock.submit() }
                }
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, 320)
                elide: Text.ElideRight
                text: view.lock.checking ? "Checking…" : view.lock.error || " "
                size: 12
                color: view.lock.error ? "#ff8a80" : Qt.rgba(1, 1, 1, 0.7)
            }
        }
    }

    // Any click wakes the password pill too.
    TapHandler { onTapped: view.ask() }
}
