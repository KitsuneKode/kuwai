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

    Behavior on implicitWidth {
        enabled: !Theme.reduceMotion
        NumberAnimation { duration: root.open ? 240 : 180; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    }

    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.wash(1); visible: root.open }

    property string query: ""
    property string confirming: ""
    property string renaming: ""
    property Item hoverRow: null

    function focusSearch() { search.forceActiveFocus(); search.selectAll(); }
    function snippet(s, q) { return OllamaService.chatSnippet(s, q); }
    onQueryChanged: OllamaService.searchChats(query)

    function dayStart(t) { const d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime(); }
    readonly property var rows: {
        const q = query.toLowerCase().trim();
        const today = dayStart(Date.now()), day = 86400000;
        const groups = [["Today", []], ["Yesterday", []], ["Previous 7 days", []], ["Older", []]];
        (OllamaService.sessions || []).forEach(s => {
            if ((s.count || 0) === 0 && s.id !== OllamaService.activeSessionId) return;
            if (q && !OllamaService.chatMatches(s, q)) return;
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
                    size: Theme.tBody
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
                height: parent.height - 30 - 32 - 20 - 24
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
                    size: Theme.tSub
                    color: Theme.textTertiary
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool isHeader: !!modelData.header
                    readonly property var chat: modelData.chat || null
                    readonly property bool selected: !!chat && chat.id === OllamaService.activeSessionId
                    activeFocusOnTab: !isHeader && !asking && !renamingThis
                    Accessible.role: Accessible.ListItem
                    Accessible.name: chat ? chat.title || "New chat" : ""
                    Accessible.selected: selected
                    Accessible.onPressAction: { if (chat) { OllamaService.switchSession(chat.id); root.sessionSelected(chat.id); } }
                    Keys.onPressed: e => {
                        if (!chat || e.isAutoRepeat) return;
                        if (e.key === Qt.Key_Return || e.key === Qt.Key_Space) { OllamaService.switchSession(chat.id); root.sessionSelected(chat.id); }
                        else if (e.key === Qt.Key_F2) root.renaming = chat.id;
                        else if (e.key === Qt.Key_Delete) root.confirming = chat.id;
                        else return;
                        e.accepted = true;
                    }
                    FocusRing { cornerRadius: Theme.r1 }
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
                        size: Theme.tFootnote
                        weight: Theme.wMedium
                        color: Theme.textTertiary
                    }

                    Rectangle {
                        visible: row.selected
                        anchors.fill: parent
                        radius: 8
                        color: Theme.wash(2)
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
                        size: Theme.tFootnote
                        color: Theme.textTertiary
                        elide: Text.ElideRight
                    }
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
                        size: Theme.tBody
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

                    Item {
                        visible: row.asking
                        anchors.fill: parent
                        focus: row.asking
                        onVisibleChanged: if (visible) forceActiveFocus()
                        Keys.onEscapePressed: root.confirming = ""
                        Label {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Delete this chat?"
                            size: Theme.tBody
                            color: Theme.textPrimary
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            Label {
                                text: "Cancel"
                                size: Theme.tSub
                                color: Theme.textTertiary
                                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.confirming = "" }
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: "Cancel"
                                Accessible.onPressAction: root.confirming = ""
                                Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.confirming = ""; e.accepted = true; } }
                                FocusRing { cornerRadius: Theme.r1 }
                            }
                            Label {
                                text: "Delete"
                                size: Theme.tSub
                                weight: Theme.wSemibold
                                color: Theme.red
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { const id = row.chat.id; root.confirming = ""; root.hoverRow = null; OllamaService.deleteSession(id); }
                                }
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: "Delete chat"
                                Accessible.description: row.chat ? row.chat.title || "" : ""
                                Accessible.onPressAction: { const id = row.chat.id; root.confirming = ""; root.hoverRow = null; OllamaService.deleteSession(id); }
                                Keys.onPressed: e => { if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { const id = row.chat.id; root.confirming = ""; root.hoverRow = null; OllamaService.deleteSession(id); e.accepted = true; } }
                                FocusRing { cornerRadius: Theme.r1 }
                            }
                        }
                    }
                }
            }
        }
    }
}
