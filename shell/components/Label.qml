// Text set the Apple way in whichever face Theme resolved (SF Pro where
// installed, else Inter): the optical size for its pixel size (Text cut
// small, Display cut large, or Inter's opsz axis), Apple's weights, and the
// face's own tracking (SF Pro's trak table; none for Inter). `rounded` is
// SF Pro Rounded for numerals, or Inter's open digits. Use this, not a bare Text.
//
//   Label { size: Theme.tHeadline; weight: Theme.wSemibold; text: "Title" }
//   Label { size: Theme.tCaption; rounded: true; text: count }
import QtQuick
import qs.config

Text {
    // Plain unless a caller asks for markup (and escapes what it puts in):
    // the default, AutoText, treated a title like `<img src="https://…">`
    // from any app, tab or thread as rich text and fetched the image.
    textFormat: Text.PlainText
    property int size: Theme.tBody
    property int weight: Theme.wRegular
    property bool rounded: false
    property bool compact: false
    property bool tabular: false
    property real extraTracking: 0
    readonly property int effectivePx: Math.round(size * Theme.textScale)
    property real opsz: Theme.opszFor(effectivePx)

    // Optical sizes as shipped: the Text cut below 20 px, Display from
    // 20 px, static weights (Theme.fontDisplay is the text face when there is
    // no separate cut; axesFor then sets Inter's opsz). (The variable SF Pro was mapped
    // once per weight × size combination: ~300 MB of the shell's memory.)
    font.family: compact ? (rounded ? Theme.compactRoundedFamily(weight) : Theme.compactFamily(weight))
                 : rounded ? Theme.roundedFamily(weight)
                 : (effectivePx >= 20 ? Theme.displayFamily(weight) : Theme.textFamily(weight))
    // Settings → Accessibility → Text size scales every label (the layout
    // grows with it: rows size to their text).
    font.pixelSize: effectivePx
    font.weight: weight
    font.hintingPreference: Font.PreferVerticalHinting
    font.letterSpacing: Theme.tracking(effectivePx, rounded, compact) + extraTracking
    font.variableAxes: Theme.axesFor(effectivePx)
    // tabular: figures that line up, keeping Inter's open digits.
    font.features: Theme.numeralFeatures(rounded, tabular)
    // FreeType, not Qt's distance-field glyph atlas: with a variable font at
    // many weight/optical-size combinations the atlas drew labels blank or
    // on top of each other; native rendering is also crisper at UI sizes.
    renderType: Text.NativeRendering
    color: Theme.textPrimary
}
