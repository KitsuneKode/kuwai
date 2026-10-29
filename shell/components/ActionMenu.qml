// An action menu that grows out of the button that opened it (Raycast's ⌘K,
// Aceternity's morphing card): one surface whose rectangle and radius go from
// the button's to the menu's on the moderate spring, the rows fading in once
// it's mostly there, and folding back into the button on close. Type to
// narrow it; ↑↓ ↵ to run; Esc closes. Items can carry their own shortcut.
//
//   ActionMenu {
//       anchorItem: actionsButton                 // what it grows out of
//       items: [{ id: "copy", label: "Copy", glyph: "…", keys: ["⇧", "↵"], danger: false, section: "Entry" }]
//       onPicked: id => …
//   }
//   menu.toggle()   menu.key(event) → handled?
import QtQuick
import qs.config

Item {
    id: menu

    property Item anchorItem
    property var items: []
    property string title: "Actions"
    property bool open: false
    property real menuW: 300
    property real maxH: 420
    property bool below: false          // open downward (from a control at the top)
    signal picked(string id)

    anchors.fill: parent
    visible: t.value > 0.002 || open
    z: 30

    function toggle() { open = !open; }
    onOpenChanged: {
        query = "";
        if (open) {
            from = anchorItem ? anchorItem.mapToItem(menu, 0, 0, anchorItem.width, anchorItem.height) : Qt.rect(width - 40, height - 30, 40, 30);
            sel = 0;
        }
        t.target = open ? 1 : 0;
        if (Theme.reduceMotion) t.settle();
    }

    // ── Items ────────────────────────────────────────────────────────────
    property string query: ""
    readonly property var shown: {
        const q = query.toLowerCase().trim();
        return items.filter(i => !q || i.label.toLowerCase().includes(q) || (i.section || "").toLowerCase().includes(q));
    }
    property int sel: 0
    onQueryChanged: sel = 0

    // Keys from whoever owns the keyboard. Returns true if handled.
    function key(event) {
        if (!open) return false;
        const k = event.key;
        if (k === Qt.Key_Escape) { open = false; }
        else if (k === Qt.Key_Down) sel = Math.min(shown.length - 1, sel + 1);
        else if (k === Qt.Key_Up) sel = Math.max(0, sel - 1);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            const it = shown[sel];
            if (it) { open = false; picked(it.id); }
        }
        else if (k === Qt.Key_Backspace) query = query.slice(0, -1);
        else if (event.text && event.text.length === 1 && event.text >= " " && !(event.modifiers & Qt.ControlModifier)) query += event.text;
        else if (!(event.modifiers & Qt.ControlModifier) || k !== Qt.Key_K) return true;     // swallow the rest
        else open = false;                                                                  // ⌃K again closes
        return true;
    }

    // ── Geometry: from the button to the menu ────────────────────────────
    property rect from: Qt.rect(0, 0, 40, 30)
    readonly property real toW: menuW
    readonly property real toH: Math.min(maxH, head.height + list.contentHeight + 12)
    // Opens upward from the button (or downward, `below`), right edges aligned.
    readonly property real toX: Math.max(8, Math.min(width - toW - 8, from.x + from.width - toW))
    readonly property real toY: below ? Math.min(height - toH - 8, from.y + from.height + 6) : Math.max(8, from.y - toH - 8)
    Spring { id: t; tier: Theme.springModerate; epsilon: 0.001 }
    function lerp(a, b, k) { return a + (b - a) * k; }

    // A click outside closes it.
    MouseArea {
        anchors.fill: parent
        enabled: menu.open
        onClicked: menu.open = false
    }

    Rectangle {
        id: frame
        x: menu.lerp(menu.from.x, menu.toX, t.value)
        y: menu.lerp(menu.from.y, menu.toY, t.value)
        width: Math.max(1, menu.lerp(menu.from.width, menu.toW, t.value))
        height: Math.max(1, menu.lerp(menu.from.height, menu.toH, t.value))
        radius: menu.lerp(menu.from.height / 2, 16, Math.min(1, t.value))
        color: Qt.rgba(0.15, 0.15, 0.18, 0.98)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        opacity: Math.min(1, t.value * 4)
        clip: true

        MouseArea { anchors.fill: parent }                           // clicks inside stay inside

        Item {
            id: inner
            // Laid out at the final size; the growing frame reveals it.
            width: menu.toW
            height: menu.toH
            x: (frame.width - width) * (1 - Math.min(1, t.value))      // rides the right edge in
            opacity: Math.max(0, Math.min(1, (t.value - 0.45) / 0.4))

            Item {
                id: head
                width: parent.width
                height: 40
                Label {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: menu.query ? menu.query : menu.title
                    size: 13
                    weight: menu.query ? Theme.wRegular : Theme.wSemibold
                    color: menu.query ? Theme.textPrimary : Theme.textSecondary
                }
                Label {
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    visible: !menu.query
                    text: "type to filter"
                    size: 11
                    color: Theme.textTertiary
                }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
            }
            ListView {
                id: list
                anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; margins: 6 }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: menu.shown
                currentIndex: menu.sel
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool lead: index === 0 || menu.shown[index - 1].section !== modelData.section
                    width: ListView.view.width
                    height: 34 + (lead && modelData.section && !menu.query ? 22 : 0)
                    Label {
                        visible: row.lead && !!row.modelData.section && !menu.query
                        x: 10; y: 6
                        text: row.modelData.section || ""
                        size: 11
                        weight: Theme.wSemibold
                        color: Theme.textTertiary
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 34
                        radius: 9
                        color: menu.sel === row.index ? (row.modelData.danger ? Qt.alpha(Theme.red, 0.85) : Qt.alpha(Theme.blue, 0.85))
                             : rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        Text {
                            id: g
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.glyph || ""
                            width: 18
                            font.family: Theme.fontGlyph
                            font.pixelSize: 14
                            color: menu.sel === row.index ? "white" : row.modelData.danger ? Theme.red : Theme.textSecondary
                        }
                        Label {
                            anchors { left: g.right; leftMargin: 8; right: keys.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text: row.modelData.label
                            size: 13
                            color: menu.sel === row.index ? "white" : row.modelData.danger ? Theme.red : Theme.textPrimary
                        }
                        Row {
                            id: keys
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 3
                            Repeater { model: row.modelData.keys || []; KeyCap { required property string modelData; text: modelData } }
                        }
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: menu.sel = row.index
                            onClicked: { menu.open = false; menu.picked(row.modelData.id); }
                        }
                    }
                }
            }
        }
    }
}
