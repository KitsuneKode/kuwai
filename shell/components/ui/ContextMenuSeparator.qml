// A hairline between groups in a ContextMenu (shadcn's ContextMenuSeparator).
// One at an end of the menu, or next to another, isn't drawn.
import QtQuick

QtObject {
    readonly property string kind: "separator"
    property bool visible: true
}
