// Text set the Apple way: variable SF Pro at the optical size for its pixel
// size (Text cut small, Display cut large), Apple's weights, and Apple's own
// per-size tracking (read from the font's trak table, see Theme). `rounded`
// switches to SF Pro Rounded for numerals. Use this, not a bare Text.
//
//   Label { size: 15; weight: Theme.wSemibold; text: "Title" }
//   Label { size: 11; rounded: true; text: count }
import QtQuick
import qs.config

Text {
    property int size: 13
    property int weight: Theme.wRegular
    property bool rounded: false
    property real extraTracking: 0
    property real opsz: Theme.opszFor(size)

    font.family: rounded ? Theme.fontRounded : Theme.fontText
    font.pixelSize: size
    font.weight: weight
    font.variableAxes: rounded ? ({}) : ({ "opsz": opsz, "wght": weight })
    font.letterSpacing: Theme.tracking(size, rounded) + extraTracking
    // FreeType, not Qt's distance-field glyph atlas: with a variable font at
    // many weight/optical-size combinations the atlas drew labels blank or
    // on top of each other; native rendering is also crisper at UI sizes.
    renderType: Text.NativeRendering
    color: Theme.textPrimary
}
