// A tray icon's menu, drawn by kuwai instead of Qt's native QMenu (which
// ignored the theme: grey Fusion rows, square corners). The entries come from
// the app over D-Bus (QsMenuOpener); this only draws and triggers them.
//
// One glass card below the icon: rows with the app's icons, check and radio
// marks, hairline separators. A submenu opens *in place* (the rows slide over,
// "‹ Back" returns), Apple's drill-down rather than cascading popups that
// fall off the island. It grows from the icon (scale 0.96 → 1 from the top,
// 160 ms ease-out) and leaves quicker; a click outside closes it.
//
//   TrayMenu { id: m; anchorItem: icon; handle: trayItem.menu; window: islandWindow }
//   m.open = true
//
// Or a menu of your own, same look and behaviour:
//   TrayMenu { anchorItem: chip; items: [{ text: "Check again", glyph: "…", triggered: () => … },
//                                         { isSeparator: true }, { text: "…", keepOpen: true, … }] }
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.config
import qs.components.ui

Item {
    id: tm
    property Item anchorItem
    property var handle                 // the root menu (SystemTrayItem.menu)
    property var items: null            // or plain actions: { text, glyph, enabled, isSeparator, keepOpen, danger, triggered }
    property var window                 // the island window (focus grab, menu count)
    property bool open: false
    property bool counted: false
    function count(on) {
        if (!window || window.menus === undefined) return;
        if (on && !counted) { counted = true; window.menus++; }
        else if (!on && counted) { counted = false; window.menus = Math.max(0, window.menus - 1); }
    }
    Component.onDestruction: count(false)
    property bool anchorHovered: false   // the pointer is on the icon that opened it
    property var stack: []              // submenus drilled into: [{ entry, title }]
    readonly property var current: stack.length ? stack[stack.length - 1].entry : handle
    signal closed()

    width: 0; height: 0
    onOpenChanged: {
        count(open);
        if (open) { stack = []; k.target = 1; }
        else { k.target = 0; closed(); }
    }
    function close() { open = false; }
    function trigger(entry) {
        if (!entry || !entry.enabled || entry.isSeparator) return;
        if (entry.hasChildren) { stack = [...stack, { entry: entry, title: entry.text }]; slide.restart(); return; }
        entry.triggered();
        if (!entry.keepOpen) close();
    }
    function back() { if (stack.length) { stack = stack.slice(0, -1); slide.restart(); } }

    // 0 hidden → 1 shown: 160 ms ease-out in, 110 ms out.
    QtObject {
        id: k
        property real target: 0
        property real value: 0
        Behavior on value { NumberAnimation { duration: k.target > 0 ? Theme.menuInMs : Theme.menuOutMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        onTargetChanged: value = target
    }

    QsMenuOpener { id: opener; menu: tm.items && !tm.stack.length ? null : (tm.current || null) }

    PopupWindow {
        id: pop
        visible: tm.anchorItem !== null && (tm.open || k.value > 0.01)
        color: "transparent"
        anchor.item: tm.anchorItem
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 10
        implicitWidth: 260
        implicitHeight: Math.min(560, card.implicitHeight) + 24

        // It goes away the way macOS menus do: a click elsewhere (focus grab),
        // the pointer leaving both the menu and its icon for a moment, or a
        // few seconds of nothing while it isn't being pointed at.
        Timer {
            interval: 650
            running: tm.open && !cardHover.hovered && !tm.anchorHovered
            onTriggered: tm.close()
        }
        Timer {
            interval: 6000
            running: tm.open && !cardHover.hovered
            onTriggered: tm.close()
        }
        HyprlandFocusGrab {
            windows: [pop, ...(tm.window ? [tm.window] : [])]
            active: tm.open
            onCleared: tm.close()
        }

        Item {
            id: card
            x: 12; y: 4
            width: pop.implicitWidth - 24
            implicitHeight: list.contentHeight + (tm.stack.length ? header.height + 4 : 0) + 12
            height: Math.min(560, implicitHeight)
            opacity: k.value
            scale: 0.96 + 0.04 * k.value
            transformOrigin: Item.Top
            HoverHandler { id: cardHover }

            MenuSurface { anchors.fill: parent }

            // Submenu header.
            Item {
                id: header
                visible: tm.stack.length > 0
                x: 6; y: 6
                width: card.width - 12; height: visible ? Theme.sp(30) : 0
                Rectangle { anchors.fill: parent; radius: Theme.r1; color: backArea.containsMouse ? Theme.pill : "transparent"; Behavior on color { ColorAnimation { duration: Theme.hoverMs } } }
                Row {
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0141}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.sp(Theme.glyphS); color: Theme.accent }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: tm.stack.length ? (tm.stack[tm.stack.length - 1].title || "Back").replace(/_/g, "") : ""; size: Theme.tBody; weight: Theme.wSemibold }
                }
                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tm.back() }
                Accessible.role: Accessible.Button
                Accessible.name: "Back"
                Accessible.description: tm.stack.length ? (tm.stack[tm.stack.length - 1].title || "").replace(/_/g, "") : ""
                Accessible.onPressAction: tm.back()
            }

            ListView {
                id: list
                x: 6
                y: header.visible ? header.y + header.height + 2 : 6
                width: card.width - 12
                height: card.height - y - 6
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                model: tm.items && !tm.stack.length ? tm.items.map(i => Object.assign({ enabled: true, isSeparator: false, hasChildren: false, buttonType: QsMenuButtonType.None, icon: "" }, i)) : opener.children
                transform: Translate { id: drift; x: 0 }
                SequentialAnimation {
                    id: slide
                    NumberAnimation { target: drift; property: "x"; from: 14; to: 0; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                }

                // One highlight for the menu (fluid hover): it glides from row to
                // row under the pointer, neutral like ActionMenu's (no accent
                // flood on every row passed over); disabled rows don't light.
                property Item hoverRow: null
                FluidHighlight { parent: list.contentItem; radius: Theme.r1; target: list.hoverRow }

                delegate: MenuRow {
                    id: row
                    required property var modelData
                    // (null for a moment while the list is replaced: a Wi-Fi scan, a device connecting)
                    readonly property var e: modelData || ({ isSeparator: true, enabled: false, text: "", hasChildren: false })
                    width: list.width
                    kind: e.isSeparator ? "separator"
                        : e.buttonType === QsMenuButtonType.RadioButton ? "radio"
                        : e.buttonType === QsMenuButtonType.CheckBox ? "check" : "item"
                    checked: e.checkState === Qt.Checked
                    glyph: e.glyph || ""
                    icon: e.icon || ""
                    // Mnemonic underscores ("_Quit") are for keyboard menus.
                    text: (e.text || "").replace(/_(?!_)/g, "")
                    submenu: !!e.hasChildren
                    danger: !!e.danger
                    can: !!e.enabled
                    selected: list.hoverRow === row
                    onPointed: on => {
                        if (on && row.can) list.hoverRow = row;
                        else if (list.hoverRow === row) list.hoverRow = null;
                    }
                    onActivated: tm.trigger(row.e)
                }
            }
        }
    }
}
