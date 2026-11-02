// Liquid-glass card, on the voxtype HUD's definitions (~/.config/voxtype/
// osd/kitsune-hud/KitsuneHud.qml), the material that reads best on this
// desktop. Hyprland blurs what's behind the surface (each rice layer
// namespace has a blur + ignore_alpha rule, see hypr/kuwai/rules.lua); this
// draws the glass on top of that blur:
//
//   base     near-black (#111114) at ~58%: dark enough that text reads on
//            any wallpaper, clear enough that the blur shows through
//   ring     a 1px DARK edge (black 55%): it draws the card's outline on
//            light backgrounds, where a light rim disappears
//   sheen    light falling from the top: a lit first pixel (the lip), a
//            glow that has faded by 40%, clear below, a little shade along
//            the bottom edge, as if lit from above
//   hairline 1px of white at 7% just inside the ring: the light half of
//            the edge, so it also reads on dark backgrounds
//   grain    off by default; a whisper (≤ 0.05) at most, where a large flat
//            surface needs tooth (assets/grain.png, made locally)
//
// All plain rectangles (no Canvas): nothing repaints on the CPU while a
// card changes size, so morphs stay cheap.
import QtQuick
import Quickshell.Widgets
import qs.config

Item {
    id: card
    property real radius: height / 2.9
    property color tint: Theme.glassTint
    property real grain: 0

    // base + dark ring
    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: card.tint
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.55)
    }

    // sheen: lip, glow, clear, shade
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, card.radius - 1)
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.20) }
            GradientStop { position: Math.min(0.04, 3 / Math.max(1, card.height)); color: Qt.rgba(1, 1, 1, 0.10) }
            GradientStop { position: 0.4;  color: Qt.rgba(1, 1, 1, 0.03) }
            GradientStop { position: 0.7;  color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, 0.12) }
        }
    }

    // inner hairline
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, card.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.07)
    }

    ClippingRectangle {
        visible: card.grain > 0
        anchors.fill: parent
        radius: card.radius
        color: "transparent"
        opacity: Math.min(0.05, card.grain)
        Image {
            anchors.fill: parent
            source: Qt.resolvedUrl("../assets/grain.png")
            fillMode: Image.Tile
            smooth: false
            cache: true
        }
    }
}
