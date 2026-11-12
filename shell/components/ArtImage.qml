// An album cover that never shows as an empty square: the art when there is
// some, a music note otherwise (a browser tab often sends no cover, and a
// paused player can drop it). Fill its parent (a ClippingRectangle with the
// radius and the pill colour behind).
//
//   ArtImage { anchors.fill: parent; source: player ? player.trackArtUrl : ""; px: 40 }
import QtQuick
import qs.config

Item {
    id: art
    property string source: ""
    property int px: 40                       // decoded size (2× the shown size)
    readonly property bool ready: img.status === Image.Ready
    Image {
        id: img
        anchors.fill: parent
        source: art.source || ""
        sourceSize: Qt.size(art.px, art.px)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Text {
        visible: !art.ready
        anchors.centerIn: parent
        text: "\u{f0387}"                         // music-note
        font.family: Theme.fontGlyph
        font.pixelSize: Math.max(Theme.tSub, Math.round(art.height * 0.5))
        color: Theme.textSecondary
    }
}
