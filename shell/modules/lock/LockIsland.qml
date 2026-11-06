// The island on the lock screen. Mostly it isn't there: it opens out of a
// dot at the top for a moment and closes back into it.
//
//   locking     a padlock, its shackle snapping shut, then it goes
//   unlocking   the shackle springs open ("Unlocked"), then the screen lifts
//   a timer     the ring emptying, its name and what's left (as an iPhone's
//               lock screen keeps one); when it ends it swells once, "Done"
//   an alarm    its name and time, Snooze and Stop (services/Alarms): the one
//               thing on the lock screen you can answer without unlocking
//
// `lock` is the lock's state (Lock.qml: leaving); `preview` skips the
// locking moment (the off-screen render).
import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: island
    required property var lock
    property bool preview: false
    anchors.horizontalCenter: parent.horizontalCenter
    y: Settings.islandStyle === "notch" ? -20 : 10
    width: pill.width; height: pill.height
    readonly property real move: Theme.reduceMotion ? 0 : 1

    // ── What it shows ────────────────────────────────────────────────────
    property bool locking: false
    Timer { id: lockedFor; interval: 1500; onTriggered: island.locking = false }
    Component.onCompleted: if (!preview) { locking = true; shackleDown.restart(); lockedFor.restart(); }
    readonly property bool unlocking: !!lock && lock.leaving

    property var done: null
    Connections { target: Timers; function onFinished(t) { island.done = t; doneFor.restart(); bump.restart(); } }
    Timer { id: doneFor; interval: 4000; onTriggered: island.done = null }
    readonly property var timer: done || Timers.next
    property var last: null
    onTimerChanged: if (timer) last = timer

    readonly property string mode: unlocking ? "unlock" : locking ? "lock" : Alarms.ringing ? "alarm" : timer ? "timer" : ""
    property string drawn: ""
    onModeChanged: { if (mode) drawn = mode; if (mode === "alarm") bump.restart(); }
    onUnlockingChanged: if (unlocking) { shackleUp.restart(); bump.restart(); }

    Spring { id: open; tier: Theme.springSlow; target: island.mode ? 1 : 0 }
    readonly property real o: Theme.reduceMotion ? (mode ? 1 : 0) : Math.max(0, open.value)
    visible: o > 0.01

    SequentialAnimation {
        id: bump
        NumberAnimation { target: pill; property: "swell"; to: 1; duration: Theme.microMs; easing.type: Easing.OutCubic }
        NumberAnimation { target: pill; property: "swell"; to: 0; duration: Theme.pulseMs; easing.type: Easing.OutBack; easing.overshoot: 2 }
    }

    // ── The padlock: drawn, so the shackle can move ──────────────────────
    // shackle: 0 shut, 1 open (lifted, swung out on its right leg).
    property real shackle: preview ? 0 : 1
    SequentialAnimation {
        id: shackleDown
        PropertyAction { target: island; property: "shackle"; value: 1 }
        PauseAnimation { duration: 380 }
        NumberAnimation { target: island; property: "shackle"; to: 0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
    }
    SequentialAnimation {
        id: shackleUp
        PropertyAction { target: island; property: "shackle"; value: 0 }
        PauseAnimation { duration: 90 }
        NumberAnimation { target: island; property: "shackle"; to: 1; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
    }
    component Padlock: Item {
        id: pad
        property color ink: "white"
        width: 16; height: 20
        // The shackle: a U, lifting and swinging out about its right leg.
        Item {
            x: 2; y: 1
            width: 12; height: 12
            transform: [
                Rotation { origin.x: 10.5; origin.y: 12; angle: -28 * island.shackle * island.move },
                Translate { y: -4 * island.shackle * island.move }
            ]
            Rectangle {
                anchors.fill: parent
                radius: 6
                color: "transparent"
                border.width: 2.2
                border.color: pad.ink
            }
        }
        Rectangle {
            x: 0; y: 8
            width: 16; height: 12; radius: 3.5
            color: pad.ink
        }
    }

    // ── The pill ─────────────────────────────────────────────────────────
    Rectangle {
        id: pill
        property real swell: 0
        readonly property real full: row.implicitWidth + 28
        anchors.horizontalCenter: parent.horizontalCenter
        width: 34 + (full - 34) * Math.min(1, island.o) + swell * 14
        height: (Settings.islandStyle === "notch" ? 54 : 36) + swell * 4
        Behavior on width { enabled: island.o >= 1 && !Theme.reduceMotion; NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        radius: 18
        color: "black"
        transform: Translate { y: -(1 - Math.min(1, island.o)) * 14 * island.move }
        opacity: Math.min(1, island.o * 2)
        clip: true

        Row {
            id: row
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Settings.islandStyle === "notch" ? 9 : 8 }
            spacing: 9
            opacity: Math.max(0, (island.o - 0.45) / 0.55)

            // Locking, unlocking.
            Padlock {
                visible: island.drawn === "lock" || island.drawn === "unlock"
                anchors.verticalCenter: parent.verticalCenter
                ink: island.drawn === "unlock" ? Theme.positive : "white"
            }
            Label {
                visible: island.drawn === "unlock"
                anchors.verticalCenter: parent.verticalCenter
                text: "Unlocked"
                size: 13; weight: Theme.wSemibold
                color: Theme.positive
            }

            // An alarm, ringing.
            Text {
                visible: island.drawn === "alarm"
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f0020}"
                font.family: Theme.fontGlyph; font.pixelSize: 16
                color: Theme.orange
            }
            Label {
                visible: island.drawn === "alarm"
                anchors.verticalCenter: parent.verticalCenter
                text: Alarms.ringing ? Alarms.ringing.label : ""
                size: 13; weight: Theme.wSemibold
            }
            Repeater {
                model: island.drawn === "alarm" ? [{ id: "snooze", text: "Snooze" }, { id: "stop", text: "Stop" }] : []
                Rectangle {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: actLabel.implicitWidth + 22; height: 24; radius: 12
                    color: modelData.id === "stop" ? Qt.alpha(Theme.orange, actArea.containsMouse ? 0.95 : 0.85) : actArea.containsMouse ? Theme.pillHover : Theme.pill
                    scale: actArea.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Label { id: actLabel; anchors.centerIn: parent; text: parent.modelData.text; size: 12; weight: Theme.wSemibold; color: parent.modelData.id === "stop" ? "#1c1c1e" : Theme.textPrimary }
                    MouseArea { id: actArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: parent.modelData.id === "stop" ? Alarms.stop() : Alarms.snooze(9) }
                }
            }

            // A timer.
            StatRing {
                visible: island.drawn === "timer"
                anchors.verticalCenter: parent.verticalCenter
                size: 18; stroke: 2.5
                value: island.done ? 1 : Timers.fraction(island.last)
                color: island.done ? Theme.positive : Theme.orange
                text: ""; label: ""
            }
            Label {
                visible: island.drawn === "timer"
                anchors.verticalCenter: parent.verticalCenter
                text: island.last ? island.last.label : ""
                size: 13; weight: Theme.wMedium
                color: Qt.rgba(1, 1, 1, 0.75)
            }
            Label {
                visible: island.drawn === "timer"
                anchors.verticalCenter: parent.verticalCenter
                text: island.done ? "Done" : island.last ? Timers.clock(Timers.remaining(island.last)) : ""
                size: 13; weight: Theme.wSemibold; rounded: true
                color: island.done ? Theme.positive : Theme.orange
                font.features: ({ "tnum": 1 })
            }
        }
    }
}
