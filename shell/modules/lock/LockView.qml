// What the lock screen shows (after the reference): the status loose in the
// top-right corner (LockCorner: Bluetooth when on, Wi-Fi or a cable, the
// charge), the island only for a moment (LockIsland: locking, unlocking, a
// timer), the date over a big rounded clock in the theme's tint, a line of
// glanceable things (weather, focus), what's playing on a glass card, the
// notifications that matter (LockNotifs), and "Press any key to unlock" at
// the bottom. A key or a click turns that line into the password
// pill (it rises out of the hint on a spring) and the clock shrinks a little
// to make room; left empty for 12 s it settles back. The wallpaper is
// blurred once and drifts slowly. A wrong password shakes the pill
// (PasswordPill) and keeps the keyboard; the right one clears the blur and
// lifts everything off the wallpaper before the lock goes.
//
// `lock` carries the state (Lock.qml); `preview` draws it without a session
// lock, for the off-screen test.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

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
    function ask() { asking = true; settle.restart(); entry.focusField(); }
    Timer { id: settle; interval: 12000; onTriggered: if (view.lock.password === "" && !view.lock.checking) view.asking = false }
    Connections { target: view.lock; function onPasswordChanged() { if (view.lock.password !== "") { view.asking = true; settle.restart(); } } }

    // Unlocking: the blur clears and the wallpaper settles to the desktop's
    // own size while everything on it lifts away; then the lock goes, onto
    // that same wallpaper (Lock.qml waits for this).
    readonly property real move: Theme.reduceMotion ? 0 : 1
    property real u: 0
    // The island's shackle springs open first (LockIsland).
    SequentialAnimation {
        id: unlockAnim
        PauseAnimation { duration: Theme.reduceMotion ? 0 : 300 }
        NumberAnimation {
            target: view; property: "u"; to: 1; duration: 440
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1]
        }
    }
    Connections { target: view.lock; function onLeavingChanged() { if (view.lock.leaving) unlockAnim.restart(); else { unlockAnim.stop(); view.u = 0; } } }

    // ── Background ───────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        scale: 1.08 - 0.08 * view.u * view.move
        property real drift: 0
        x: drift * (1 - view.u)
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
        // The same picture sharp, decoded only for the unlock.
        Image {
            anchors.fill: parent
            visible: view.u > 0
            opacity: view.u
            source: visible ? wall.source : ""
            sourceSize: Qt.size(view.width, view.height)
            fillMode: Image.PreserveAspectCrop
        }
        SequentialAnimation on drift {
            running: !Theme.reduceMotion
            loops: Animation.Infinite
            NumberAnimation { from: -30; to: 30; duration: 45000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 30; to: -30; duration: 45000; easing.type: Easing.InOutSine }
        }
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.22 * (1 - view.u)) }

    // ── What sits on the wallpaper (lifts away on unlock) ────────────────
    Item {
        id: content
        anchors.fill: parent
        opacity: 1 - view.u
        transform: Translate { y: -view.u * 40 * view.move }
        scale: 1 + view.u * 0.03 * view.move

        // ── Status in the corner, a timer in the island ──────────────────────
        LockCorner {
            id: corner
            shown: view.preview ? 1 : 0
            NumberAnimation on shown {
                running: !view.preview
                from: 0; to: 1; duration: Theme.pulseMs
                easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut
            }
        }

        // ── Date, time, glance ───────────────────────────────────────────────
        // Asking for the password, it makes room: smaller, a little higher.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.11) - ask.value * 24 * view.move
            transformOrigin: Item.Top
            scale: 1 - ask.value * 0.16 * view.move
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
                duration: Theme.breatheMs; stagger: 60
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
                    visible: Notifs.muted
                    spacing: 7
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0594}"; font.family: Theme.fontGlyph; font.pixelSize: 18; color: view.tint }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: "Focus"; size: 18; weight: Theme.wMedium; color: view.tint }
                }
            }
        }

        // ── Now playing ──────────────────────────────────────────────────────
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.46)
            spacing: 12
            LockMedia { anchors.horizontalCenter: parent.horizontalCenter }
            LockNotifs { anchors.horizontalCenter: parent.horizontalCenter; onTapped: item => { view.lock.openAfter = item; view.ask(); } }
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

            PasswordPill {
                id: entry
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                opacity: Math.max(0, Math.min(1, (ask.value - 0.3) / 0.6))
                transform: Translate { y: (1 - Math.min(1, ask.value)) * 14 }
                lock: view.lock
                preview: view.preview
                placeholder: view.lock.openAfter ? "Unlock to open " + (view.lock.openAfter.app || "it") : "Enter Password"
                onActivity: view.ask()
                onDismissed: view.asking = false
            }
        }
    }

    // Above what lifts away: it says "Unlocked" until the lock goes.
    LockIsland { lock: view.lock; preview: view.preview }

    // Any click wakes the password pill too.
    TapHandler { onTapped: view.ask() }

    // Volume and brightness keys: their HUD (the session's own is under the lock).
    LockOsd {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 72 }
        z: 50
    }
}
