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

    // Apple's optical sizes as Apple ships them: the Text cut below 20 px,
    // Display from 20 px, static weights. (The variable SF Pro was mapped
    // once per weight × size combination: ~300 MB of the shell's memory.)
    font.family: rounded ? Theme.fontRounded : (size >= 20 ? Theme.fontDisplay : Theme.fontText)
    // Settings → Accessibility → Text size scales every label (the layout
    // grows with it: rows size to their text).
    font.pixelSize: Math.round(size * Theme.textScale)
    font.weight: weight
    font.letterSpacing: Theme.tracking(size, rounded) + extraTracking
    // FreeType, not Qt's distance-field glyph atlas: with a variable font at
    // many weight/optical-size combinations the atlas drew labels blank or
    // on top of each other; native rendering is also crisper at UI sizes.
    renderType: Text.NativeRendering
    color: Theme.textPrimary
}
