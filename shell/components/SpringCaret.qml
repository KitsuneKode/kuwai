// A caret that glides to where the cursor goes instead of jumping (Skiper
// UI's smooth caret input, skiper106), on a stiff, critically damped spring:
// typing reads as one continuous motion. It rests solid while you type and
// only starts blinking after a pause, like macOS. Reduced motion: it jumps.
//
//   TextInput { cursorDelegate: SpringCaret {} }
import QtQuick
import qs.config

Rectangle {
    id: caret
    width: 2
    radius: 1
    color: Theme.blue

    Behavior on x {
        enabled: !Theme.reduceMotion
        SpringAnimation { spring: 9; damping: 0.85; epsilon: 0.2 }
    }

    // Solid while moving; blink (530ms, the platform rate) once idle.
    property bool idle: false
    onXChanged: { idle = false; rest.restart(); opacity = 1; }
    Timer { id: rest; interval: 600; onTriggered: caret.idle = true }
    SequentialAnimation on opacity {
        running: caret.idle && caret.visible
        loops: Animation.Infinite
        onStopped: caret.opacity = 1
        NumberAnimation { to: 0; duration: 120; easing.type: Easing.OutQuad }
        PauseAnimation { duration: 410 }
        NumberAnimation { to: 1; duration: 120; easing.type: Easing.OutQuad }
        PauseAnimation { duration: 410 }
    }
}
