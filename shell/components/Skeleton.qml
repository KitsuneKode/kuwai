// A placeholder while something loads: the shape of what's coming, with a
// soft highlight sweeping across (Theme.shimmerMs, the one loading sweep;
// linear: it's progress, not motion to follow). Reduced motion: it holds
// still. Size it like the real thing.
//
// Many at once (a gallery's cards): give them one `phase` (0 → 1) from one
// animation, so they sweep together and one clock runs, not one per card.
//   Skeleton { width: 120; height: 12 }
//   Skeleton { phase: panel.sheen; … }
import QtQuick
import qs.config

Rectangle {
    id: sk
    property bool running: visible
    property real phase: -1                 // ≥ 0: driven from outside
    radius: Math.min(height / 2, 8)
    color: Qt.rgba(1, 1, 1, 0.07)
    clip: true

    Rectangle {
        id: sweep
        width: Math.max(60, sk.width * 0.45)
        height: sk.height
        x: sk.phase >= 0 ? -width + sk.phase * (sk.width + width) : -width
        opacity: Theme.reduceMotion ? 0 : 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.07) }
            GradientStop { position: 1.0; color: "transparent" }
        }
        NumberAnimation on x {
            running: sk.running && sk.phase < 0 && !Theme.reduceMotion
            from: -sweep.width; to: sk.width
            duration: Theme.shimmerMs
            loops: Animation.Infinite
        }
    }
}
