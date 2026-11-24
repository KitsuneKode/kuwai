// Liquid-glass card, on the voxtype HUD's definitions (~/.config/voxtype/
// osd/kitsune-hud/KitsuneHud.qml), the material that reads best on this
// desktop. Hyprland blurs what's behind the surface (each kuwai layer
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
// Single-pass SDF ShaderEffect (shaders/glasscard.frag): tint, dark ring,
// sheen, bottom shade, directional rim and procedural grain in one draw call.
import QtQuick
import qs.config

ShaderEffect {
    id: card
    property string level: "regular"
    readonly property var spec: Theme.materialSpec(level)
    property real radius: height / 2.9
    property color tint: spec.tint
    property color rimColor: spec.rim
    property real sheen: spec.sheen
    property real darkRing: spec.darkRing
    property real grain: 0
    readonly property vector2d size: Qt.vector2d(width, height)
    visible: width > 1 && height > 1
    blending: true
    fragmentShader: Qt.resolvedUrl("../shaders/glasscard.frag.qsb")
}
