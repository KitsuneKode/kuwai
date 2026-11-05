// A tray icon's menu, drawn by the rice instead of Qt's native QMenu (which
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

Item {
    id: tm
    property Item anchorItem
    property var handle                 // the root menu (SystemTrayItem.menu)
    property var items: null            // or plain actions: { text, glyph, enabled, isSeparator, keepOpen, danger, triggered }
    property var window                 // the island window (focus grab, menu count)
    property bool open: false
    property bool anchorHovered: false   // the pointer is on the icon that opened it
    property var stack: []              // submenus drilled into: [{ entry, title }]
    readonly property var current: stack.length ? stack[stack.length - 1].entry : handle
    signal closed()

    width: 0; height: 0
    onOpenChanged: {
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
        Behavior on value { NumberAnimation { duration: k.target > 0 ? 160 : 110; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
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
            implicitHeight: list.contentHeight + (tm.stack.length ? 34 : 0) + 12
            height: Math.min(560, implicitHeight)
            opacity: k.value
            scale: 0.96 + 0.04 * k.value
            transformOrigin: Item.Top
            HoverHandler { id: cardHover }

            // Shadow, then the glass.
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    readonly property real s: 2 + index * 5
                    x: -s; y: -s + 6 + index * 2
                    width: card.width + s * 2; height: card.height + s * 2
                    radius: 14 + s
                    color: Qt.rgba(0, 0, 0, 0.09)
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: 14
                color: Qt.rgba(0.07, 0.07, 0.08, 0.97)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.09)
            }

            // Submenu header.
            Item {
                id: header
                visible: tm.stack.length > 0
                x: 6; y: 6
                width: card.width - 12; height: visible ? 30 : 0
                Rectangle { anchors.fill: parent; radius: 8; color: backArea.containsMouse ? Theme.pill : "transparent" }
                Row {
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0141}"; font.family: Theme.fontGlyph; font.pixelSize: 14; color: Theme.accent }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: tm.stack.length ? (tm.stack[tm.stack.length - 1].title || "Back").replace(/_/g, "") : ""; size: 13; weight: Theme.wSemibold }
                }
                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tm.back() }
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
                    NumberAnimation { target: drift; property: "x"; from: 14; to: 0; duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    // (null for a moment while the list is replaced: a Wi-Fi scan, a device connecting)
                    readonly property var e: modelData || ({ isSeparator: true, enabled: false, text: "", hasChildren: false })
                    width: list.width
                    height: e.isSeparator ? 9 : 30

                    Rectangle {
                        visible: row.e.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8; width: parent.width - 16; height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }
                    Rectangle {
                        visible: !row.e.isSeparator
                        anchors.fill: parent
                        radius: 8
                        color: rowArea.containsMouse && row.e.enabled ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                    }
                    // Check / radio mark, the app's icon, the label, a submenu chevron.
                    Item {
                        visible: !row.e.isSeparator
                        anchors.fill: parent
                        opacity: row.e.enabled ? 1 : 0.38
                        Text {
                            id: mark
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            text: row.e.buttonType === QsMenuButtonType.None ? ""
                                : row.e.checkState === Qt.Checked ? (row.e.buttonType === QsMenuButtonType.RadioButton ? "\u{f0765}" : "\u{f012c}")
                                : (row.e.buttonType === QsMenuButtonType.RadioButton ? "\u{f0766}" : "")
                            font.family: Theme.fontGlyph; font.pixelSize: 12
                            color: Theme.accent
                        }
                        Text {
                            visible: !!row.e.glyph
                            x: 26; anchors.verticalCenter: parent.verticalCenter
                            text: row.e.glyph || ""
                            font.family: Theme.fontGlyph; font.pixelSize: 14
                            color: row.e.danger ? Theme.orange : Theme.textSecondary
                        }
                        IconImage {
                            id: icon
                            visible: !!row.e.icon && !row.e.glyph
                            x: 26; anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 16
                            source: row.e.icon || ""
                            asynchronous: true
                        }
                        Label {
                            anchors { left: parent.left; leftMargin: row.e.icon || row.e.glyph ? 50 : 26; right: chev.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            // Mnemonic underscores ("_Quit") are for keyboard menus.
                            text: (row.e.text || "").replace(/_(?!_)/g, "")
                            size: 13
                            color: row.e.danger ? Theme.orange : Theme.textPrimary
                        }
                        Text {
                            id: chev
                            visible: row.e.hasChildren
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            text: "\u{f0142}"
                            font.family: Theme.fontGlyph; font.pixelSize: 13
                            color: Theme.textTertiary
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        enabled: !row.e.isSeparator
                        hoverEnabled: true
                        cursorShape: row.e.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: tm.trigger(row.e)
                    }
                }
            }
        }
    }
}
