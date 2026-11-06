// One popover for the whole shell: a glass card that grows from an anchor
// (the island's bell, a chip, a mark) into its own popup window, so it is
// never clipped by the island body. Everything popovers kept getting wrong
// lives here once:
//
//   • the focus grab names *this* popup window (a grab on `parent` let the
//     first click inside count as "outside" and close it: the bell bug)
//   • the island stays grown while it's open (window.menus counts it)
//   • it goes away like macOS menus: a click elsewhere, the pointer leaving
//     card and anchor for a moment (sticky: false), or idle; Esc closes
//   • it grows from the anchor (scale .96 → 1 from the top, 160 ms ease-out)
//     and leaves quicker (110 ms); content never resizes while it opens
//
//   Popover {
//       anchorItem: bell; window: hover.bar; open: list.shown
//       sticky: true                   // opened by a deliberate click/hold
//       onClosed: list.shown = false
//       Column { width: parent.width; … }   // the content; sets the height
//   }
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.config

Item {
    id: po
    property Item anchorItem
    // Optional: open below this item (the island body) instead of just under
    // the anchor, still centred on the anchor. Under the bell alone it landed
    // on the hover view's lower row and covered it.
    property Item belowItem: null
    property var window                  // the island window (focus grab, menu count)
    property bool open: false
    property bool anchorHovered: false   // the pointer is on what opened it
    // Opened on purpose (right-click, hold): it stays while you look away;
    // only a click elsewhere, Esc or idle closes it.
    property bool sticky: false
    property int cardWidth: 320
    property int maxHeight: 420
    property int padding: 12
    property int idleMs: 8000
    property real cardRadius: 16
    readonly property bool shown: open || k.value > 0.01
    readonly property bool hovered: cardHover.hovered
    default property alias content: body.data
    signal closed()

    width: 0; height: 0

    // Close by asking the owner (it owns `open`, usually a binding).
    function close() { if (open) closed(); }

    property bool counted: false
    // Where the anchor's centre is, in belowItem's coordinates: measured each
    // time it opens. A mapToItem() binding is evaluated once (it doesn't
    // follow layout), so the list opened under where the bell was before the
    // hover view laid out: far to the left.
    property real anchorX: 0
    function place() {
        if (belowItem && anchorItem) anchorX = anchorItem.mapToItem(belowItem, anchorItem.width / 2, 0).x;
        popWin.anchor.updateAnchor();
    }
    onOpenChanged: {
        if (open) place();
        k.target = open ? 1 : 0;
        if (open && !counted && window) { counted = true; window.menus++; }
        else if (!open && counted && window) { counted = false; window.menus = Math.max(0, window.menus - 1); }
    }
    Component.onDestruction: if (counted && window) window.menus = Math.max(0, window.menus - 1)

    QtObject {
        id: k
        property real target: 0
        property real value: 0
        Behavior on value { enabled: !Theme.reduceMotion; NumberAnimation { duration: k.target > 0 ? 160 : 110; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        onTargetChanged: value = target
    }

    PopupWindow {
        id: popWin
        visible: !!po.anchorItem && po.shown
        color: "transparent"
        anchor.item: po.belowItem || po.anchorItem
        anchor.rect.x: po.belowItem ? po.anchorX : 0
        anchor.rect.y: 0
        anchor.rect.width: po.belowItem ? 1 : (po.anchorItem ? po.anchorItem.width : 0)
        anchor.rect.height: po.belowItem ? po.belowItem.height : (po.anchorItem ? po.anchorItem.height : 0)
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 10
        implicitWidth: po.cardWidth + 20
        implicitHeight: card.height + 16

        Timer {
            interval: 650
            running: po.open && !po.sticky && !cardHover.hovered && !po.anchorHovered
            onTriggered: po.close()
        }
        Timer {
            interval: po.idleMs
            running: po.open && !cardHover.hovered && !po.anchorHovered
            onTriggered: po.close()
        }
        HyprlandFocusGrab {
            windows: [popWin, ...(po.window ? [po.window] : [])]
            active: po.open
            onCleared: po.close()
        }

        Item {
            id: card
            x: 10; y: 4
            width: po.cardWidth
            height: Math.min(po.maxHeight, body.childrenRect.height + po.padding * 2)
            opacity: k.value
            scale: Theme.reduceMotion ? 1 : 0.96 + 0.04 * k.value
            transformOrigin: Item.Top
            focus: po.open
            Keys.onEscapePressed: po.close()
            HoverHandler { id: cardHover }

            // Near-solid, like TrayMenu: a popup is no layer surface, so
            // Hyprland's blur doesn't reach it, and see-through glass let the
            // window behind read through the text.
            Rectangle {
                anchors.fill: parent
                radius: po.cardRadius
                color: Qt.rgba(0.07, 0.07, 0.08, 0.97)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.09)
            }
            Item {
                id: body
                x: po.padding; y: po.padding
                width: card.width - po.padding * 2
                height: card.height - po.padding * 2
            }
        }
    }
}
