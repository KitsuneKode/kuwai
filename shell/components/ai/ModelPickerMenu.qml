// The model picker: grows out of the model pill, the rice's ActionMenu motion
// (one surface: the pill's rectangle and radius become the card's on the
// moderate spring, rows fade in once it's mostly there, and it folds back into
// the pill on close). Each row says what the model can really do, from Ollama
// (tools, thinking, vision), its size, and whether it's loaded right now.
// Type to filter (Kobra's ranking: exact, prefix, substring, subsequence);
// ↑↓ move the fluid highlight, ↵ picks, Esc or ⌃K closes.
// Refs: T3 Code ModelPickerContent / ModelListRow, AI Elements model-selector.
import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: menu

    property Item anchorItem
    property bool open: false
    readonly property real menuW: 340
    signal closed()

    anchors.fill: parent
    visible: t.value > 0.002 || open
    z: 40

    function toggle() { open = !open; }
    onOpenChanged: {
        query = "";
        if (open) {
            from = anchorItem ? anchorItem.mapToItem(menu, 0, 0, anchorItem.width, anchorItem.height) : Qt.rect(20, height - 60, 120, 30);
            sel = Math.max(0, shown.findIndex(m => m.id === OllamaService.model));
            keyboard = false;
        } else {
            closed();
        }
        t.target = open ? 1 : 0;
        if (Theme.reduceMotion) t.settle();
    }

    // ── Models ───────────────────────────────────────────────────────────
    function describe(name) {
        const i = OllamaService.modelInfo[name] || {};
        const caps = i.capabilities || [];
        const tools = caps.indexOf("tools") >= 0, think = caps.indexOf("thinking") >= 0, vision = caps.indexOf("vision") >= 0;
        let what = tools ? "Tools" + (think ? ", thinking" : "") + (vision ? ", vision" : "")
                 : vision ? "Vision, no tools"
                 : think ? "Thinking, no tools" : "Chat only";
        return what + (i.sizeGb ? " · " + i.sizeGb + " GB" : "");
    }
    // The recommended models first, with what each is for; then everything else installed.
    readonly property var models: {
        const have = OllamaService.availableModels || [];
        const picks = OllamaService.curated.filter(c => have.indexOf(c.id) >= 0).map(c => ({
            id: c.id, label: OllamaService.modelLabel(c.id), role: c.role, detail: c.note,
            loaded: OllamaService.isLoaded(c.id), other: false }));
        const rest = have.filter(n => !OllamaService.curated.some(c => c.id === n)).map((n, i) => ({
            id: n, label: OllamaService.modelLabel(n), role: "", detail: describe(n),
            loaded: OllamaService.isLoaded(n), other: true, firstOther: i === 0 && picks.length > 0 }));
        return picks.concat(rest);
    }

    // Kobra's ranking: exact 0, prefix 1, substring 2, letters in order 3, else no match.
    function rank(text, q) {
        const s = text.toLowerCase();
        if (s === q) return 0;
        if (s.startsWith(q)) return 1;
        if (s.indexOf(q) >= 0) return 2;
        let j = 0;
        for (let i = 0; i < s.length && j < q.length; i++) if (s[i] === q[j]) j++;
        return j === q.length ? 3 : 9;
    }
    property string query: ""
    readonly property var shown: {
        const q = query.toLowerCase().trim();
        if (!q) return models;
        return models.map(m => ({ m: m, r: Math.min(rank(m.label, q), rank(m.id, q)) }))
            .filter(x => x.r < 9).sort((a, b) => a.r - b.r).map(x => x.m);
    }
    property int sel: 0
    property bool keyboard: false
    onQueryChanged: sel = 0

    // ↵ switches this chat to the model (history is plain text; a smaller window just
    // compacts sooner). ⌃↵ forks the chat into a new one on that model, leaving this as it was.
    function pick(m) {
        if (!m) return;
        OllamaService.model = m.id;
        open = false;
    }
    function pickFork(m) {
        if (!m) return;
        OllamaService.forkAt(-1, m.id);
        open = false;
    }

    // Keys from whoever owns the keyboard (the prompt). Returns true if handled.
    function key(event) {
        if (!open) return false;
        const k = event.key;
        if (k === Qt.Key_Escape || ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_K)) open = false;
        else if (k === Qt.Key_Down) { keyboard = true; sel = Math.min(shown.length - 1, sel + 1); }
        else if (k === Qt.Key_Up) { keyboard = true; sel = Math.max(0, sel - 1); }
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) pickFork(shown[sel]);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) pick(shown[sel]);
        else if (k === Qt.Key_Backspace) query = query.slice(0, -1);
        else if (event.text && event.text.length === 1 && event.text >= " " && !(event.modifiers & Qt.ControlModifier)) query += event.text;
        return true;
    }

    // ── Geometry: from the pill to the card, opening upward ──────────────
    property rect from: Qt.rect(0, 0, 120, 30)
    readonly property real toW: menuW
    readonly property real toH: Math.min(460, head.height + list.contentHeight + 14)
    readonly property real toX: Math.max(8, Math.min(width - toW - 8, from.x))
    readonly property real toY: Math.max(8, from.y - toH - 8)
    Spring { id: t; tier: Theme.springModerate; epsilon: 0.001 }
    function lerp(a, b, k) { return a + (b - a) * k; }

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

        MouseArea { anchors.fill: parent }

        Item {
            id: inner
            width: menu.toW
            height: menu.toH
            y: frame.height - height        // rides the bottom edge up, out of the pill
            opacity: Math.max(0, Math.min(1, (t.value - 0.45) / 0.4))

            Item {
                id: head
                width: parent.width
                height: 40
                Label {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: menu.query ? menu.query : "Model"
                    size: 13
                    weight: menu.query ? Theme.wRegular : Theme.wSemibold
                    color: menu.query ? Theme.textPrimary : Theme.textSecondary
                }
                Label {
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: menu.query ? (menu.shown.length ? "" : "No match")
                        : OllamaService.messages.length > 0 ? "↵ switch · ⌃↵ new chat with it" : "Type to filter"
                    size: 11
                    color: Theme.textTertiary
                }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
            }

            ListView {
                id: list
                anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; margins: 6 }
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                model: menu.shown
                currentIndex: menu.sel
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                FluidHighlight {
                    parent: list.contentItem
                    target: menu.open && list.currentItem ? list.currentItem.hit : null
                    ring: menu.keyboard
                    radius: 10
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool current: modelData.id === OllamaService.model
                    readonly property bool sep: !!modelData.firstOther && !menu.query
                    readonly property Item hit: hitBox
                    Item { id: hitBox; width: parent.width; height: 52; anchors.bottom: parent.bottom }
                    width: ListView.view.width
                    height: 52 + (sep ? 28 : 0)

                    // "Other installed" above the first model that isn't a pick.
                    Label {
                        visible: row.sep
                        x: 12; y: 10
                        text: "Other installed"
                        size: 11
                        weight: Theme.wMedium
                        color: Theme.textTertiary
                    }

                    Column {
                        anchors { left: parent.left; leftMargin: 12; right: marks.left; rightMargin: 8; bottom: parent.bottom; bottomMargin: 9 }
                        spacing: 2
                        Row {
                            width: parent.width
                            spacing: 8
                            Label {
                                text: row.modelData.label
                                size: 13
                                weight: Theme.wMedium
                                color: row.modelData.other ? Theme.textSecondary : Theme.textPrimary
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, parent.width - roleTag.width - 8)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                id: roleTag
                                visible: !!row.modelData.role
                                width: visible ? roleText.implicitWidth + 12 : 0
                                height: 18
                                radius: 9
                                color: /Uncensored/.test(row.modelData.role) ? Qt.alpha(Theme.orange, 0.16) : Qt.alpha(Theme.accent, 0.16)
                                anchors.verticalCenter: parent.verticalCenter
                                Label {
                                    id: roleText
                                    anchors.centerIn: parent
                                    text: row.modelData.role || ""
                                    size: 10
                                    weight: Theme.wSemibold
                                    color: /Uncensored/.test(row.modelData.role) ? Theme.orange : Theme.accent
                                }
                            }
                        }
                        Label {
                            width: parent.width
                            text: row.modelData.detail
                            size: 12
                            color: Theme.textTertiary
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        id: marks
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter; verticalCenterOffset: row.sep ? 14 : 0 }
                        spacing: 10
                        Row {
                            visible: row.modelData.loaded
                            spacing: 5
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle { width: 6; height: 6; radius: 3; color: Theme.green; anchors.verticalCenter: parent.verticalCenter }
                            Label { text: "Loaded"; size: 11; color: Theme.textTertiary; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Icon {
                            visible: row.current
                            name: "check"
                            style: "bold"
                            size: 14
                            color: Theme.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: { menu.keyboard = false; menu.sel = row.index; }
                        onClicked: menu.pick(row.modelData)
                    }
                }
            }
        }
    }
}
