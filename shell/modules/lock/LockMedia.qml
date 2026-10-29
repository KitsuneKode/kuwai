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
    width: 360; height: 150

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    PwNodePeakMonitor {
        id: peak
        node: Pipewire.defaultAudioSink
        enabled: media.visible && media.player && media.player.isPlaying
    }
    readonly property real level: peak.peaks && peak.peaks.length ? Math.max(...peak.peaks) : (peak.peak || 0)

    Rectangle {
        anchors.fill: parent
        radius: 24
        color: Qt.rgba(0, 0, 0, 0.35)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)
    }
    ClippingRectangle {
        id: art
        x: 16; y: 16
        width: 72; height: 72; radius: 14
        color: Qt.rgba(1, 1, 1, 0.1)
        Image { anchors.fill: parent; source: media.player ? (media.player.trackArtUrl || "") : ""; sourceSize: Qt.size(144, 144); fillMode: Image.PreserveAspectCrop; asynchronous: true }
    }
    Column {
        anchors { left: art.right; leftMargin: 14; right: parent.right; rightMargin: 16; top: art.top; topMargin: 4 }
        spacing: 2
        Label { width: parent.width; elide: Text.ElideRight; text: media.player ? (media.player.trackTitle || "Unknown") : ""; size: 15; weight: Theme.wSemibold }
        Label { width: parent.width; elide: Text.ElideRight; text: media.player ? (media.player.trackArtist || media.player.identity || "") : ""; size: 13; color: Qt.rgba(1, 1, 1, 0.7) }
        // The visualiser: 20 bars riding the level.
        Row {
            topPadding: 8
            spacing: 3
            Repeater {
                model: 20
                Rectangle {
                    required property int index
                    readonly property real shape: 0.45 + 0.55 * Math.sin(Math.PI * (index + 0.5) / 20)
                    property real jitter: 1
                    anchors.bottom: parent.bottom
                    width: 4; radius: 2
                    height: 3 + 20 * Math.min(1, media.level * shape * jitter * 1.6)
                    color: Theme.accent
                    opacity: 0.85
                    Behavior on height { NumberAnimation { duration: 90 } }
                    Timer { running: peak.enabled && !Theme.reduceMotion; interval: 120 + (index % 5) * 30; repeat: true; onTriggered: parent.jitter = 0.6 + Math.random() * 0.6 }
                }
            }
        }
    }
    Row {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 12 }
        spacing: 22
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
                color: bArea.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                scale: bArea.pressed ? 0.9 : 1
                Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                Text { anchors.centerIn: parent; text: b.modelData.g; font.family: Theme.fontGlyph; font.pixelSize: b.modelData.big ? 24 : 18; color: "white" }
                MouseArea { id: bArea; anchors.fill: parent; enabled: b.modelData.ok; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.modelData.on() }
            }
        }
    }
}
