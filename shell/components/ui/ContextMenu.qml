// A right-click menu: shadcn's ContextMenu, in kuwai's glass. What a row
// offers, reachable with the pointer as well as the keys.
//
//   Item {
//       id: row
//       ContextMenu {
//           id: rowMenu
//           target: row                   // right-click on it opens the menu where the pointer is
//           bounds: panel                 // the surface it stays inside (default: the window)
//           title: "linux-zen"
//           ContextMenuLabel { text: "linux-zen" }
//           ContextMenuItem { text: "Review changes"; glyph: "…"; shortcut: "↵"; onTriggered: … }
//           ContextMenuCheckboxItem { text: "Include in update"; checked: …; onToggled: on => … }
//           ContextMenuSeparator {}
//           ContextMenuItem { text: "Forget it"; variant: "destructive"; onTriggered: … }
//       }
//       activeFocusOnTab: true
//       Keys.onPressed: e => { if (rowMenu.handleKey(e)) return; … }   // Menu key, Shift+F10
//   }
//
// Anatomy (each its own file, as shadcn splits them): ContextMenu holds
// ContextMenuItem (an action; `variant: "destructive"`), ContextMenuCheckboxItem
// (on/off), ContextMenuLabel (a heading), ContextMenuSeparator. An entry with
// `visible: false` isn't drawn; separators left at an end or doubled aren't
// either. When any entry has a glyph or a check, every text lines up after
// that column.
//
// Behaviour (Radix's): opens at the pointer, flipped where it would run out of
// `bounds`; nothing is lit until the pointer or a key lights a row; ↑↓ Home
// End move, a letter jumps to the next row starting with it, ↵ or Space
// chooses, Esc or a click anywhere else closes and gives the keyboard back to
// whoever had it. Choosing closes it, then runs the entry.
//
// It is drawn in the window, over its `bounds` (like ActionMenu), not as a popup
// surface: a popup would need its own focus grab, and a second grab ends the
// island's, which closes the panel. Nothing exists until it opens: the trigger
// is one MouseArea on the target; the card is loaded on open and unloaded once
// it has faded out, by a Loader the menu owns (a card made with createObject
// outlived its menu when the shell quit, and Qt crashed deleting it). The root
// is not an Item, so it never lays itself out.
import QtQuick
import qs.config
import qs.components
import "contextMenu.mjs" as Menu

QtObject {
    id: menu

    required property Item target
    property Item bounds: null
    property bool enabled: true
    property string title: ""
    property real minWidth: Theme.sp(200)
    default property list<QtObject> content
    readonly property Item overlay: surface.item
    readonly property bool open: overlay !== null && overlay.shown
    signal opened()
    signal closed()

    // Entries from a list (a menu of devices, of outputs): plain objects after
    // the declared ones (contextMenu.mjs `plain` says their fields).
    property var items: []
    readonly property var entries: Menu.arrange(Array.from(content).concat(Menu.plain(items)))
    readonly property bool lead: entries.some(e => !!e.glyph || e.kind === "checkbox")

    // Opens at (x, y) in the target's coordinates. From the keyboard (no point),
    // it opens under the target's leading edge with its first row lit.
    function popup(x, y) {
        const keys = x === undefined;
        if (!enabled || !target || !target.visible || Menu.first(entries) < 0) return;
        const host = bounds || (target.Window.window ? target.Window.window.contentItem : null);
        if (!host) return;
        // A row partly scrolled out of its list opens its menu at the edge that shows.
        const q = target.mapToItem(host, keys ? Theme.s4 : x, keys ? target.height : y);
        const p = Qt.point(Math.max(0, Math.min(host.width, q.x)), Math.max(0, Math.min(host.height, q.y)));
        if (!overlay || !overlay.shown) giveBack = target.Window.activeFocusItem;
        where = host;                         // loads the card (synchronously)
        if (!overlay) return;
        overlay.at = p;
        overlay.shown = true;
        overlay.byKeys = keys;
        overlay.current = keys ? Menu.first(entries) : -1;
        overlay.forceActiveFocus();
        opened();
    }
    function close() {
        if (!overlay || !overlay.shown) return;
        overlay.shown = false;
        if (giveBack) giveBack.forceActiveFocus();
        giveBack = null;
        closed();
    }
    // The keys that open a context menu on the focused target: Menu, Shift+F10.
    function handleKey(e) {
        if (open || !enabled) return false;
        if (e.key === Qt.Key_Menu || (e.key === Qt.Key_F10 && (e.modifiers & Qt.ShiftModifier))) {
            popup();
            e.accepted = true;
            return true;
        }
        return false;
    }
    function choose(i) {
        const e = entries[i];
        if (!Menu.actionable(e)) return;
        close();
        if (e.kind === "checkbox") e.toggled(!e.checked);
        else e.triggered();
    }
    function key(e) {
        const o = overlay;
        if (!o) return;
        e.accepted = true;
        const k = e.key;
        if (k === Qt.Key_Escape || k === Qt.Key_Tab || k === Qt.Key_Backtab || k === Qt.Key_Menu) close();
        else if (k === Qt.Key_Down) { o.byKeys = true; o.current = Menu.step(entries, o.current, 1); }
        else if (k === Qt.Key_Up) { o.byKeys = true; o.current = Menu.step(entries, o.current, -1); }
        else if (k === Qt.Key_Home || k === Qt.Key_PageUp) { o.byKeys = true; o.current = Menu.first(entries); }
        else if (k === Qt.Key_End || k === Qt.Key_PageDown) { o.byKeys = true; o.current = Menu.last(entries); }
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (o.current >= 0) choose(o.current); }
        else if (e.text && e.text.length === 1 && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            o.byKeys = true;
            o.current = Menu.typeahead(entries, o.current, e.text);
        }
    }

    property Item giveBack: null
    property Item where: null                // the surface the card is drawn over while it's out

    readonly property Loader surface: Loader {
        parent: menu.where
        anchors.fill: parent
        z: 1000
        active: menu.where !== null
        sourceComponent: menu.card
    }

    // The trigger: a right-click on the target. It takes the press (so the
    // island's "right-click goes back" doesn't also run) and nothing else:
    // left clicks and hover pass through to what's under it.
    readonly property MouseArea trigger: MouseArea {
        parent: menu.target
        anchors.fill: parent
        z: 1
        enabled: menu.enabled
        acceptedButtons: Qt.RightButton
        onPressed: m => menu.popup(m.x, m.y)
        Accessible.ignored: true            // the keys' way in is the row's own (handleKey: Menu, Shift+F10)
    }

    readonly property Component card: Component {
        FocusScope {
            id: ov
            property point at
            property bool shown: true
            property bool byKeys: false
            property int current: -1
            readonly property real margin: Theme.s2
            readonly property real pad: Theme.s1
            readonly property real natural: {
                let w = 0;
                for (let i = 0; i < rep.count; i++) { const r = rep.itemAt(i); if (r) w = Math.max(w, r.natural); }
                return w + 2 * pad;
            }
            readonly property real cardW: Math.min(Math.max(menu.minWidth, natural), Theme.sp(320), width - 2 * margin)
            readonly property real cardH: Math.min(rows.implicitHeight + 2 * pad, height - 2 * margin)
            readonly property var spot: Menu.place(at.x, at.y, cardW, cardH, width, height, margin)

            focus: true
            Keys.onPressed: e => menu.key(e)

            // 0 → 1 on open (ease-out, enterMs), back to 0 quicker; then gone.
            property real k: 0
            Behavior on k { NumberAnimation { duration: ov.shown ? Theme.enterMs : Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            Component.onCompleted: k = 1
            onShownChanged: k = shown ? 1 : 0
            onKChanged: if (!shown && k === 0) menu.where = null

            // A press anywhere else closes it, and does nothing more.
            MouseArea {
                anchors.fill: parent
                enabled: ov.shown
                acceptedButtons: Qt.AllButtons
                onPressed: m => { m.accepted = true; menu.close(); }
                onWheel: w => w.accepted = true
                Accessible.ignored: true        // Esc does this from the keys
            }

            Item {
                id: frame
                readonly property bool floats: true          // it covers the panel (the rehearsal reads this)
                x: ov.spot.x; y: ov.spot.y
                width: ov.cardW; height: ov.cardH
                opacity: ov.k
                // It grows from the corner at the pointer (Radix's transform origin); reduced motion: a fade.
                transform: Scale {
                    origin.x: ov.spot.ox * frame.width
                    origin.y: ov.spot.oy * frame.height
                    xScale: Theme.reduceMotion || !ov.shown ? 1 : 0.96 + 0.04 * ov.k
                    yScale: xScale
                }
                Accessible.role: Accessible.PopupMenu
                Accessible.name: menu.title

                Elevation { target: frame; radius: Theme.r2; strength: 0.5 }
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.r2
                    color: Theme.menuSurface
                    border.width: 1
                    border.color: Theme.menuEdge
                }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: m => m.accepted = true }

                Flickable {
                    id: flick
                    anchors { fill: parent; margins: ov.pad }
                    contentHeight: rows.implicitHeight
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    FluidHighlight {
                        parent: flick.contentItem
                        radius: Theme.r1
                        ring: ov.byKeys
                        target: ov.current >= 0 && ov.current < rep.count ? rep.itemAt(ov.current) : null
                    }

                    Column {
                        id: rows
                        width: flick.width
                        Repeater {
                            id: rep
                            model: menu.entries
                            Item {
                                id: row
                                required property var modelData
                                required property int index
                                readonly property var e: modelData
                                readonly property bool can: Menu.actionable(e)
                                readonly property bool danger: e.variant === "destructive"
                                readonly property real indent: menu.lead ? Theme.sp(28) : Theme.s2
                                readonly property real natural: e.kind === "separator" ? 0
                                    : indent + words.implicitWidth + (keys.visible ? Theme.s4 + keys.implicitWidth : 0) + Theme.s2
                                width: rows.width
                                height: e.kind === "separator" ? Theme.s2 + 1 : e.kind === "label" ? Theme.sp(26) : Theme.sp(30)
                                onCanChanged: if (!can && ov.current === index) ov.current = -1

                                Rectangle {
                                    visible: row.e.kind === "separator"
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: -ov.pad; width: parent.width + 2 * ov.pad; height: 1
                                    color: Theme.menuEdge
                                }
                                // The leading column: the entry's glyph, or a checkbox's check.
                                Text {
                                    textFormat: Text.PlainText
                                    visible: row.e.kind === "checkbox" ? !!row.e.checked : !!row.e.glyph && row.e.kind === "item"
                                    width: row.indent; horizontalAlignment: Text.AlignHCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.e.kind === "checkbox" ? "\u{f012c}" : (row.e.glyph || "")
                                    font.family: Theme.fontGlyph; font.pixelSize: Theme.sp(Theme.glyphS)
                                    color: !row.can ? Theme.textTertiary : row.danger ? Theme.red : row.e.kind === "checkbox" ? Theme.textPrimary : Theme.textSecondary
                                }
                                Label {
                                    id: words
                                    visible: row.e.kind !== "separator"
                                    anchors { left: parent.left; leftMargin: row.indent; right: keys.visible ? keys.left : parent.right; rightMargin: keys.visible ? Theme.s4 : Theme.s2; verticalCenter: parent.verticalCenter }
                                    elide: Text.ElideRight
                                    text: row.e.text || ""
                                    size: row.e.kind === "label" ? Theme.tFootnote : Theme.tBody
                                    weight: row.e.kind === "label" ? Theme.wSemibold : Theme.wRegular
                                    color: row.e.kind === "label" || !row.can ? Theme.textTertiary : row.danger ? Theme.redText : Theme.textPrimary
                                }
                                // shadcn's ContextMenuShortcut: the key the surface answers to, quiet, at the end.
                                Label {
                                    id: keys
                                    visible: !!row.e.shortcut && row.e.kind !== "label" && row.e.kind !== "separator"
                                    anchors { right: parent.right; rightMargin: Theme.s2; verticalCenter: parent.verticalCenter }
                                    text: row.e.shortcut || ""
                                    size: Theme.tFootnote
                                    color: Theme.textTertiary
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: row.can
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: { ov.byKeys = false; ov.current = row.index; }
                                    onExited: if (ov.current === row.index && !ov.byKeys) ov.current = -1
                                    onClicked: menu.choose(row.index)
                                }
                                Accessible.role: row.e.kind === "separator" ? Accessible.Separator : row.e.kind === "label" ? Accessible.StaticText : Accessible.MenuItem
                                Accessible.name: row.e.text || ""
                                Accessible.description: row.e.shortcut || ""
                                Accessible.checkable: row.e.kind === "checkbox"
                                Accessible.checked: !!row.e.checked
                                Accessible.selected: ov.current === row.index
                                Accessible.ignored: row.e.kind === "separator"
                                Accessible.onPressAction: menu.choose(row.index)
                            }
                        }
                    }
                }
                ScrollFade { flickable: flick }
            }
        }
    }
}
