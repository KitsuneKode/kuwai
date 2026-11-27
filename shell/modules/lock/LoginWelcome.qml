// "Welcome back" and your name, over your wallpaper as a login opens into it.
// GreeterView plays it in (`progress` 0 → 1); greeter.qml's cover shows it
// at 1, so the lock's last frame and the cover over the handover match.
import QtQuick
import QtQuick.Effects
import qs.config
import qs.components

Column {
    id: welcome

    required property string name
    property real progress: 1
    property real motion: 1

    spacing: Theme.lockClockGap
    opacity: Math.max(0, Math.min(1, (progress - 0.35) / 0.4))
    visible: opacity > 0
    transform: Translate { y: (1 - Math.min(1, welcome.progress)) * 10 * welcome.motion }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Welcome back"
        size: Theme.tLockHeadline; weight: Theme.wSemibold
        color: "white"
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowOpacity: 0.5 }
    }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: welcome.name
        size: Theme.tLockLine; weight: Theme.wMedium
        color: Qt.rgba(1, 1, 1, 0.8)
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowOpacity: 0.5 }
    }
}
