// A placeholder while something loads: the shape of what's coming, with a
// soft highlight sweeping across (1.4s, linear: it's progress, not motion
// to follow). Reduced motion: it holds still. Size it like the real thing.
import QtQuick
import qs.config

Rectangle {
    id: sk
    property bool running: visible
    radius: Math.min(height / 2, 8)
    color: Qt.rgba(1, 1, 1, 0.07)
    clip: true

    Rectangle {
        id: sweep
        width: Math.max(60, sk.width * 0.45)
        height: sk.height
        x: -width
        opacity: Theme.reduceMotion ? 0 : 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.07) }
            GradientStop { position: 1.0; color: "transparent" }
        }
        NumberAnimation on x {
            running: sk.running && !Theme.reduceMotion
            from: -sweep.width; to: sk.width
            duration: 1400
            loops: Animation.Infinite
        }
    }
}
