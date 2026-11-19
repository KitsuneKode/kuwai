// An on/off choice in a ContextMenu (shadcn's ContextMenuCheckboxItem): a
// check in the leading column while on. Choosing it emits `toggled` with the
// new state; bind `checked` to where the state lives.
//
//   ContextMenuCheckboxItem { text: "Include in update"; checked: chosen; onToggled: on => … }
import QtQuick

QtObject {
    readonly property string kind: "checkbox"
    property string text
    property string shortcut: ""
    property bool checked: false
    property bool enabled: true
    property bool visible: true
    signal toggled(bool checked)
}
