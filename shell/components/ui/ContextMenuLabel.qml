// A heading inside a ContextMenu (shadcn's ContextMenuLabel): what the menu
// is about ("linux-zen"), not something to choose.
import QtQuick

QtObject {
    readonly property string kind: "label"
    property string text
    property bool visible: true
}
