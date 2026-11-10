// The chats, as in ChatGPT / Claude: search, then the chats grouped by day
// (Today, Yesterday, Previous 7 days, Older), one gliding hover highlight
// (FluidHighlight). Hover a chat for its trash; the row then asks
// "Delete this chat?" in place (Delete / Cancel, Esc cancels): nothing is
// deleted on one stray click. Empty new chats don't clutter the list.
import QtQuick
import qs.config
import qs.components
import qs.services

Rectangle {
    id: root

    property bool open: true
    signal newChatRequested()
    signal sessionSelected(string id)

    implicitWidth: open ? 260 : 0
    implicitHeight: parent ? parent.height : 600
    clip: true
    color: Qt.rgba(0.04, 0.04, 0.05, 0.55)

    // Opens in 240 ms, closes quicker (180); both ease out (an ease-in close lags).
    Behavior on implicitWidth {
        enabled: !Theme.reduceMotion
        NumberAnimation { duration: root.open ? 240 : 180; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    }

    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.07); visible: root.open }

    property string query: ""
    property string confirming: ""     // id of the chat asking "Delete?"
    property string renaming: ""       // id of the chat being renamed (double-click)
    property Item hoverRow: null

    function focusSearch() { search.forceActiveFocus(); search.selectAll(); }
    // Where a search hit in a chat's messages (not its title): ~70 characters around it.
    function snippet(s, q) {
        if (!q || (s.title || "").toLowerCase().indexOf(q) >= 0) return "";
        for (const m of (s.messages || [])) {
            const t = (m.text || "").replace(/\s+/g, " ");
            const i = t.toLowerCase().indexOf(q);
            if (i >= 0) return (i > 24 ? "…" : "") + t.slice(Math.max(0, i - 24), i + 46) + (i + 46 < t.length ? "…" : "");
        }
        return "";
    }

    function dayStart(t) { const d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime(); }
    readonly property var rows: {
        const q = query.toLowerCase().trim();
        const today = dayStart(Date.now()), day = 86400000;
        const groups = [["Today", []], ["Yesterday", []], ["Previous 7 days", []], ["Older", []]];
        (OllamaService.sessions || []).forEach(s => {
            const msgs = s.messages || [];
            if (msgs.length === 0 && s.id !== OllamaService.activeSessionId) return;
            if (q) {
                const hay = ((s.title || "") + " " + msgs.map(m => m.text || "").join(" ")).toLowerCase();
                if (hay.indexOf(q) < 0) return;
            }
            const t = s.updatedAt || 0;
            const g = t >= today ? 0 : t >= today - day ? 1 : t >= today - 7 * day ? 2 : 3;
            groups[g][1].push(s);
        });
        const out = [];
        groups.forEach(g => {
            if (!g[1].length) return;
            out.push({ header: g[0] });
            g[1].sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0)).forEach(s => out.push({ chat: s }));
        });
        return out;
    }

    Item {
        width: 260
        height: parent.height
        opacity: root.open ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.open ? 180 : 120; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Item {
                width: parent.width
                height: 30
                Label {
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Chats"
                    size: 13
                    weight: Theme.wSemibold
                    color: Theme.textSecondary
                }
                MessageAction {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30
                    icon: "note-pencil"
                    onClicked: { OllamaService.newChat(); root.newChatRequested(); }
                }
            }

            // Search
            Rectangle {
                width: parent.width
                height: 32
                radius: 9
                color: Qt.rgba(1, 1, 1, search.activeFocus ? 0.08 : 0.05)
                border.width: 1
                border.color: search.activeFocus ? Qt.alpha(Theme.accent, 0.5) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                Icon { x: 9; anchors.verticalCenter: parent.verticalCenter; name: "magnifying-glass"; size: 13; color: Theme.textTertiary }
                TextInput {
                    id: search
                    anchors { left: parent.left; leftMargin: 30; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    color: Theme.textPrimary
                    font.family: Theme.fontText
                    font.pixelSize: 13
                    selectionColor: Qt.alpha(Theme.accent, 0.5)
                    clip: true
                    onTextChanged: root.query = text
                    Keys.onEscapePressed: event => { if (text) { text = ""; event.accepted = true; } else event.accepted = false; }
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !search.text
                        text: "Search"
                        color: Theme.textTertiary
                        font.family: Theme.fontText
                        font.pixelSize: 13
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - 30 - 32 - 20 - 24     // header, search, two gaps, the column's margins
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.rows

                FluidHighlight {
                    parent: list.contentItem
                    target: root.hoverRow
                    radius: 8
                }

                Label {
                    visible: root.rows.length === 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 24
                    text: root.query ? "No chats match" : "No chats yet"
                    size: 12
                    color: Theme.textTertiary
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool isHeader: !!modelData.header
                    readonly property var chat: modelData.chat || null
                    readonly property bool selected: !!chat && chat.id === OllamaService.activeSessionId
                    readonly property bool asking: !!chat && root.confirming === chat.id
                    readonly property bool renamingThis: !!chat && root.renaming === chat.id
                    width: ListView.view.width
                    readonly property string hit: !!chat && root.query ? root.snippet(chat, root.query.toLowerCase().trim()) : ""
                    height: isHeader ? (index === 0 ? 24 : 34) : (hit ? 50 : 34)

                    Label {
                        visible: row.isHeader
                        x: 8
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        text: row.modelData.header || ""
                        size: 11
                        weight: Theme.wMedium
                        color: Theme.textTertiary
                    }

                    Rectangle {
                        visible: row.selected
                        anchors.fill: parent
                        radius: 8
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    TextInput {
                        id: renameField
                        visible: row.renamingThis
                        anchors { left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        color: Theme.textPrimary
                        font.family: Theme.fontText
                        font.pixelSize: 13
                        selectionColor: Qt.alpha(Theme.accent, 0.5)
                        clip: true
                        onVisibleChanged: if (visible) { text = row.chat ? row.chat.title : ""; selectAll(); forceActiveFocus(); }
                        Keys.onReturnPressed: { OllamaService.renameSession(row.chat.id, text); root.renaming = ""; }
                        Keys.onEscapePressed: event => { root.renaming = ""; event.accepted = true; }
                        onActiveFocusChanged: if (!activeFocus && row.renamingThis) root.renaming = ""
                    }
                    Rectangle {
                        visible: row.renamingThis
                        anchors.fill: parent
                        radius: 8
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Theme.accent, 0.5)
                    }

                    Label {
                        visible: !!row.hit && !row.asking && !row.renamingThis
                        anchors { left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 7 }
                        text: row.hit
                        size: 11
                        color: Theme.textTertiary
                        elide: Text.ElideRight
                    }
                    // Answering in the background (you're in another chat), or an
                    // answer that came while you were away: a ring, then a dot.
                    readonly property bool working: !!row.chat && OllamaService.streaming && OllamaService.draftSessionId === row.chat.id && !row.selected
                    readonly property bool fresh: !!row.chat && !!OllamaService.unread[row.chat.id]
                    Item {
                        id: chatState
                        visible: !row.isHeader && !row.asking && !row.renamingThis && (row.working || row.fresh)
                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.hit ? -8 : 0 }
                        width: visible ? 8 : 0; height: 8
                        Rectangle { visible: row.fresh && !row.working; anchors.fill: parent; radius: 4; color: Theme.accent }
                        Rectangle {
                            visible: row.working
                            anchors.fill: parent; radius: 4
                            color: "transparent"; border.width: 1.5; border.color: Theme.accent
                            Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.accent; x: 2.5; y: -0.5 }
                            RotationAnimation on rotation { running: row.working && !Theme.reduceMotion; loops: Animation.Infinite; from: 0; to: 360; duration: Theme.spinMs }
                        }
                    }
                    Label {
                        visible: !row.isHeader && !row.asking && !row.renamingThis
                        anchors { left: chatState.right; leftMargin: chatState.visible ? 7 : 0; right: trash.left; rightMargin: 4; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.hit ? -8 : 0 }
                        text: row.chat ? (row.chat.title && row.chat.title !== "New Chat" ? row.chat.title : "New chat") : ""
                        size: 13
                        weight: row.selected ? Theme.wMedium : Theme.wRegular
                        color: row.selected ? Theme.textPrimary : Theme.textSecondary
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        enabled: !row.isHeader && !row.asking && !row.renamingThis
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: {
                            if (containsMouse) root.hoverRow = row;
                            else if (root.hoverRow === row) root.hoverRow = null;
                        }
                        onClicked: { OllamaService.switchSession(row.chat.id); root.sessionSelected(row.chat.id); }
                        onDoubleClicked: root.renaming = row.chat.id
                    }

                    MessageAction {
                        id: trash
                        visible: !row.isHeader && !row.asking && !row.renamingThis
                        opacity: rowArea.containsMouse || hovered ? 1 : 0
                        readonly property bool hovered: trashHover.hovered
                        HoverHandler { id: trashHover }
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28
                        icon: "trash"
                        Behavior on opacity { NumberAnimation { duration: Theme.colorMs } }
                        onClicked: root.confirming = row.chat.id
                    }

                    // "Delete this chat?" in place.
                    Item {
                        visible: row.asking
                        anchors.fill: parent
                        focus: row.asking
                        // focus: alone doesn't take it from the search field: Esc never reached here.
                        onVisibleChanged: if (visible) forceActiveFocus()
                        Keys.onEscapePressed: root.confirming = ""
                        Label {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Delete this chat?"
                            size: 13
                            color: Theme.textPrimary
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            Label {
                                text: "Cancel"
                                size: 12
                                color: Theme.textTertiary
                                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.confirming = "" }
                            }
                            Label {
                                text: "Delete"
                                size: 12
                                weight: Theme.wSemibold
                                color: Theme.red
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { const id = row.chat.id; root.confirming = ""; root.hoverRow = null; OllamaService.deleteSession(id); }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
