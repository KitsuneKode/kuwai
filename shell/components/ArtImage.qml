// An album cover that never shows as an empty square: the art when there is
// some, a music note otherwise (a browser tab often sends no cover, and a
// paused player can drop it). Fill its parent (a ClippingRectangle with the
// radius and the pill colour behind).
//
//   ArtImage { anchors.fill: parent; source: player ? player.trackArtUrl : ""; px: 40 }
//
// With `player` (and room: px ≥ 80), a player that sends no cover shows a
// frame of its window instead of the note — a film in a browser looks like
// the film. Local (screencopy of that one window, no network), refreshed every
// 1.5 s only while it's on screen; nothing captured when hidden. Never pass
// `player` on the lock screen: it would show the window behind the lock.
//   ArtImage { …; player: hover.player; px: 96 }
import QtQuick
import Quickshell.Wayland
import qs.config
import qs.services

Item {
    id: art
    property string source: ""
    property int px: 40                       // decoded size (2× the shown size)
    property var player: null
    readonly property bool ready: img.status === Image.Ready
    readonly property var win: player && !art.source && art.px >= 80 && art.visible ? Media.windowShowing(player) : null
    readonly property bool framed: !!(win && win.wayland) && shot.hasContent
    Image {
        id: img
        anchors.fill: parent
        source: art.source || ""
        sourceSize: Qt.size(art.px, art.px)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    // A video frame, cropped to the slot like a cover (centred, never
    // stretched; the slot's ClippingRectangle cuts the sides).
    ScreencopyView {
        id: shot
        readonly property real aspect: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 9
        anchors.centerIn: parent
        width: aspect >= art.width / Math.max(1, art.height) ? art.height * aspect : art.width
        height: aspect >= art.width / Math.max(1, art.height) ? art.height : art.width / aspect
        visible: !art.ready && art.framed
        captureSource: art.win && art.win.wayland ? art.win.wayland : null
        live: false
    }
    // Every 1.5 s while shown; reduced motion: the first frame only.
    Timer {
        interval: 1500; repeat: !Theme.reduceMotion; triggeredOnStart: true
        running: !!shot.captureSource && art.visible
        onTriggered: shot.captureFrame()
    }
    Text {
        visible: !art.ready && !art.framed
        anchors.centerIn: parent
        text: "\u{f0387}"                         // music-note
        font.family: Theme.fontGlyph
        font.pixelSize: Math.max(Theme.tSub, Math.round(art.height * 0.5))
        color: Theme.textSecondary
    }
}
