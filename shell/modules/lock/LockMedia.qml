// Now playing, on the lock screen (bottom right): the art, the song, a
// level visualiser that moves with what you hear, and play / skip, so music
// can be paused or skipped without unlocking. Hidden when nothing plays.
// The visualiser is driven by the output's real level (PipeWire peaks), its
// bars shaped so the middle reads loudest; not a spectrum (no FFT here).
import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import qs.config
import qs.components

Item {
    id: media
    readonly property var player: Mpris.players.values.find(p => p.playbackState === MprisPlaybackState.Playing) || Mpris.players.values.find(p => p.playbackState === MprisPlaybackState.Paused) || null
    visible: player !== null
    width: 430; height: 76

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    PwNodePeakMonitor {
        id: peak
        node: Pipewire.defaultAudioSink
        enabled: media.visible && media.player && media.player.isPlaying
    }
    readonly property real level: peak.peaks && peak.peaks.length ? Math.max(...peak.peaks) : (peak.peak || 0)
    HoverHandler { id: over }

    // Glass: a light frost over the blurred wallpaper, a hairline edge.
    Rectangle {
        anchors.fill: parent
        radius: 22
        color: Qt.rgba(1, 1, 1, over.hovered ? 0.2 : 0.14)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.22)
        Behavior on color { ColorAnimation { duration: Theme.colorMs } }
    }
    ClippingRectangle {
        id: art
        x: 13; anchors.verticalCenter: parent.verticalCenter
        width: 50; height: 50; radius: 12
        color: Qt.rgba(1, 1, 1, 0.12)
        Image { anchors.fill: parent; source: media.player ? (media.player.trackArtUrl || "") : ""; sourceSize: Qt.size(100, 100); fillMode: Image.PreserveAspectCrop; asynchronous: true }
    }
    Column {
        anchors { left: art.right; leftMargin: 14; right: trail.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 2
        Label { width: parent.width; elide: Text.ElideRight; text: media.player ? (media.player.trackTitle || "Unknown") : ""; size: 16; weight: Theme.wSemibold }
        Label { width: parent.width; elide: Text.ElideRight; text: media.player ? (media.player.trackArtist || media.player.identity || "") : ""; size: 13; color: Qt.rgba(1, 1, 1, 0.72) }
    }
    Item {
        id: trail
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        width: 104; height: 34
        // Bars that follow what you hear; the controls when the pointer is here.
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            opacity: over.hovered ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    property real jitter: 1
                    anchors.bottom: parent.bottom
                    width: 4; radius: 1.5
                    height: Math.max(4, 18 * Math.min(1, media.level * jitter * 1.8))
                    color: Theme.accent
                    Behavior on height { NumberAnimation { duration: 100 } }
                    Timer { running: peak.enabled && !Theme.reduceMotion; interval: 120 + index * 40; repeat: true; onTriggered: parent.jitter = 0.55 + Math.random() * 0.7 }
                }
            }
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            opacity: over.hovered ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            Repeater {
                model: [
                    { g: "\u{f04ae}", on: () => media.player.previous(), ok: media.player && media.player.canGoPrevious },
                    { g: media.player && media.player.isPlaying ? "\u{f03e4}" : "\u{f040a}", on: () => media.player.togglePlaying(), ok: media.player && media.player.canTogglePlaying, big: true },
                    { g: "\u{f04ad}", on: () => media.player.next(), ok: media.player && media.player.canGoNext }
                ]
                Rectangle {
                    id: b
                    required property var modelData
                    width: 34; height: 34; radius: 17
                    opacity: modelData.ok ? 1 : 0.35
                    color: bArea.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : "transparent"
                    scale: bArea.pressed ? 0.9 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Text { anchors.centerIn: parent; text: b.modelData.g; font.family: Theme.fontGlyph; font.pixelSize: b.modelData.big ? 22 : 17; color: "white" }
                    MouseArea { id: bArea; anchors.fill: parent; enabled: b.modelData.ok; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.modelData.on() }
                }
            }
        }
    }
}
