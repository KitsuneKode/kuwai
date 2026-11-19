// One action in a ContextMenu (shadcn's ContextMenuItem).
//
//   ContextMenuItem { text: "Review changes"; glyph: "\u{f0208}"; shortcut: "↵"; onTriggered: … }
//   ContextMenuItem { text: "Forget"; variant: "destructive"; onTriggered: … }
//
// `shortcut` only shows the key the surface already answers to; it binds nothing.
import QtQuick

QtObject {
    readonly property string kind: "item"
    property string text
    property string glyph: ""
    property string shortcut: ""
    property bool enabled: true
    property bool visible: true
    property string variant: "default"   // default · destructive (red: what can't be taken back)
    signal triggered()
}
