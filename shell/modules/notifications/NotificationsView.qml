// The center's Notifications tab: filter chips, then every notification
// grouped by app (folded into stacks), with one highlight gliding under the
// pointer or the keyboard selection.
//
// Search and filters narrow the list and fan every group out. Keyboard (sent
// here by Center): ↑↓ select, ↵ open, ⌦ (or ⌫ on an empty query) dismiss,
// →← expand or fold the selected group, ⇥ next filter.
import QtQuick
import QtQuick.Effects
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: view

    required property var center                    // the Center scope (query, reveal)
    property bool hosting: true                     // the hosting monitor's copy (Center)

    // Rows and groups talk to the view through these.
    readonly property var terms: center.terms
    readonly property bool instant: center.instant
    function highlight(text) { return center.highlight(text); }

    // ── Filters ──────────────────────────────────────────────────────────
    property string filter: "all"                   // all | unread | important
    readonly property var filters: ["all", "unread", "important"]
    readonly property bool narrowed: terms.length > 0 || filter !== "all"
    onFilterChanged: center.snap()

    function passesFilter(i) {
        if (filter === "unread") return i.time > Notifs.lastSeen;
        if (filter === "important") return i.severity === "critical" || i.severity === "warning";
        return true;
    }
    function matches(i) {
        if (!passesFilter(i)) return false;
        return center.matchesText(i.app + " " + i.title + " " + i.body.replace(/<[^>]*>/g, "") + " " + i.status);
    }
    readonly property int importantCount: Notifs.items.filter(i => i.severity === "critical" || i.severity === "warning").length

    // Newest app first; within an app, newest first. Only matching ones.
    readonly property var groups: {
        const map = new Map();
        for (const i of Notifs.items) {
            if (i.discard || !matches(i)) continue;
            if (!map.has(i.app)) map.set(i.app, { key: i.app, app: i.app, icon: i.icon, items: [] });
            map.get(i.app).items.push(i);
        }
        return [...map.values()];
    }
    readonly property int resultCount: groups.reduce((n, g) => n + g.items.length, 0)

    property var expandedGroups: ({})
    function isExpanded(key) { return narrowed || !!expandedGroups[key]; }
    function setExpanded(key, on) {
        const next = Object.assign({}, expandedGroups);
        next[key] = on;
        expandedGroups = next;
    }

    // ── Selection and hover ──────────────────────────────────────────────
    readonly property var visibleItems: {
        const out = [];
        for (const g of groups) {
            if (isExpanded(g.key)) out.push(...g.items);
            else out.push(g.items[0]);
        }
        return out;
    }
    property var selected: null
    property Item selectedRow: null
    property Item hoverRow: null
    property bool keyboard: false                   // the last move came from keys
    readonly property int selectedIndex: visibleItems.indexOf(selected)
    onVisibleItemsChanged: if (selected && selectedIndex < 0) selected = visibleItems[0] || null

    function setHover(row, on) {
        if (on) { hoverRow = row; keyboard = false; }
        else if (hoverRow === row) hoverRow = null;
    }

    // Esc: first back to All, then (false) the center closes.
    function back() {
        if (filter === "all") return false;
        filter = "all";
        return true;
    }
    function reset() {
        filter = "all";
        selected = null;
        selectedRow = null;
        hoverRow = null;
        keyboard = false;
        expandedGroups = {};
        list.contentY = 0;
    }
    function selectFirst() { selected = visibleItems[0] || null; }

    function move(step) {
        if (!visibleItems.length) return;
        keyboard = true;
        const at = selectedIndex < 0 ? (step > 0 ? -1 : 0) : selectedIndex;
        selected = visibleItems[Math.max(0, Math.min(visibleItems.length - 1, at + step))];
        const g = groups.findIndex(x => x.items.includes(selected));
        if (g >= 0) list.positionViewAtIndex(g, ListView.Contain);
        // A tall group can still leave the row itself half out of view.
        Qt.callLater(() => {
            const r = view.selectedRow;
            if (!r || !r.visible) return;
            const y = r.mapToItem(list.contentItem, 0, 0).y;
            if (y + r.height > list.contentY + list.height - 6) list.contentY = y + r.height - list.height + 6;
            else if (y < list.contentY + 6) list.contentY = Math.max(0, y - 6);
        });
    }

    function key(event, queryEmpty) {
        const k = event.key;
        if (k === Qt.Key_Down) move(1);
        else if (k === Qt.Key_Up) move(-1);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (selected) Notifs.openItem(selected); }
        else if (k === Qt.Key_Delete || (k === Qt.Key_Backspace && queryEmpty)) removeSelected();
        else if (k === Qt.Key_Right && queryEmpty && selected) setExpanded(selected.app, true);
        else if (k === Qt.Key_Left && queryEmpty && selected) setExpanded(selected.app, false);
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab)
            filter = filters[(filters.indexOf(filter) + (k === Qt.Key_Backtab ? 2 : 1)) % 3];
        else return false;
        return true;
    }

    function removeSelected() {
        if (!selected) return;
        const gone = selected;
        selected = visibleItems[selectedIndex + 1] || visibleItems[selectedIndex - 1] || null;
        if (gone.popup) Notifs.dismiss(gone);
        else Notifs.remove(gone);
    }

    function clearAll() { clearOut.start(); }

    // For Center's diagnostics.
    readonly property Item filterRowItem: filterRow
    readonly property int groupCount: groups.length
    readonly property int listCount: list.count
    readonly property real listContentHeight: list.contentHeight
    // How tall it wants to be (the card fits it): the filters, then the
    // list, or the empty state's room.
    // (A list builds rows only for the room it has, so contentHeight reads
    // short right after opening: more than a few groups simply wants the
    // full card, and a few want at least their rows' typical height.)
    readonly property real naturalHeight: filterRow.height + 14 + (list.count === 0 ? 220
        : list.count > 3 ? 100000 : Math.max(list.contentHeight, list.count * 96) + 8)

    // ── Filters row ──────────────────────────────────────────────────────
    Row {
        id: filterRow
        x: 2
        opacity: view.center.revealAt(80)
        spacing: 6

        Repeater {
            model: [
                // The tab already says how many are unread: no second and
                // third copy here. Only Important has a count of its own.
                { id: "all", label: "All", n: 0 },
                { id: "unread", label: "Unread", n: 0 },
                { id: "important", label: "Important", n: view.importantCount }
            ]
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: view.filter === modelData.id
                height: 28; radius: 14
                width: chipRow.implicitWidth + 22
                scale: chipArea.pressed ? 0.97 : 1
                Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                color: on ? Qt.rgba(1, 1, 1, 0.92) : chipArea.containsMouse ? Theme.pillHover : Theme.pill
                Behavior on color { ColorAnimation { duration: 80 } }
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 5
                    Label {
                        text: chip.modelData.label
                        size: 12
                        weight: chip.on ? Theme.wSemibold : Theme.wMedium
                        color: chip.on ? "#111114" : Theme.textPrimary
                    }
                    Label {
                        visible: chip.modelData.n > 0
                        text: chip.modelData.n
                        size: 12
                        font.features: ({ "tnum": 1 })
                        color: chip.on ? Qt.rgba(0, 0, 0, 0.5) : Theme.textTertiary
                    }
                }
                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.filter = chip.modelData.id
                }
            }
        }
    }
    // Right of the filters: the result count while narrowed, otherwise
    // Do Not Disturb (Apple's Focus indigo when on) and Clear all.
    Label {
        visible: view.narrowed
        anchors { right: parent.right; rightMargin: 4; verticalCenter: filterRow.verticalCenter }
        text: view.resultCount === 1 ? "1 result" : view.resultCount + " results"
        size: 12
        color: Theme.textTertiary
    }
    Row {
        visible: !view.narrowed
        anchors { right: parent.right; verticalCenter: filterRow.verticalCenter }
        spacing: 6
        opacity: view.center.revealAt(80)
        PillButton {
            height: 28
            width: 28
            glyph: "\u{f0594}"                     // moon
            text: ""
            tint: Notifs.dnd ? "#5e5ce6" : "transparent"
            onClicked: Notifs.dnd = !Notifs.dnd
        }
        PillButton {
            visible: Notifs.items.length > 0
            height: 28
            text: "Clear"
            onClicked: view.clearAll()
        }
    }

    // Clear all: the list falls away, then empties.
    SequentialAnimation {
        id: clearOut
        ParallelAnimation {
            NumberAnimation { target: list; property: "opacity"; to: 0; duration: Theme.springSlow.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            NumberAnimation { target: listShift; property: "y"; to: Theme.reduceMotion ? 0 : 12; duration: Theme.springSlow.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }
        ScriptAction { script: { Notifs.clearAll(); list.opacity = 1; listShift.y = 0; } }
    }

    // The fade's shape: opaque, then the bottom 28 px going to nothing.
    Item {
        id: listFade
        visible: false
        layer.enabled: true
        width: list.width; height: list.height
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "white" }
                GradientStop { position: Math.max(0, 1 - 28 / Math.max(1, listFade.height)); color: "white" }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    // ── List ─────────────────────────────────────────────────────────────
    ListView {
        id: list
        anchors { left: parent.left; right: parent.right; top: filterRow.bottom; bottom: parent.bottom; topMargin: 14 }
        clip: true
        spacing: 18
        boundsBehavior: Flickable.DragAndOvershootBounds
        // More below: the last rows fade out instead of being cut at an edge.
        layer.enabled: contentHeight > height + 4 && !atYEnd
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: listFade
            maskThresholdMin: 0
            maskSpreadAtMin: 1
        }
        transform: Translate { id: listShift }
        model: ScriptModel { values: view.groups; objectProp: "key" }

        delegate: CenterGroup {
            center: view
            expanded: view.isExpanded(modelData.key)
            canFold: !view.narrowed
            onToggled: view.setExpanded(modelData.key, !view.expandedGroups[modelData.key])
            // Product reveal: groups fade in a step apart, no rise.
            opacity: view.center.revealAt(120 + Math.min(index, 6) * Theme.revealStepMs)
        }

        remove: Transition {
            enabled: !view.instant
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.springModerate.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }
        displaced: Transition {
            enabled: !view.instant
            NumberAnimation { properties: "y"; duration: Theme.reflowMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }

        FluidHighlight {
            parent: list.contentItem
            target: view.keyboard ? view.selectedRow : (view.hoverRow || null)
            ring: view.keyboard && target !== null
        }
    }

    ScrollHint {
        flickable: list
        anchors { right: parent.right; rightMargin: -10; top: list.top; bottom: list.bottom }
    }

    // Empty: nothing at all, or nothing matching.
    Column {
        visible: view.groups.length === 0
        anchors.centerIn: list
        spacing: 8
        opacity: view.center.revealAt(120)
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 56; height: 56; radius: 28
            color: Theme.platterDim
            Text {
                anchors.centerIn: parent
                text: view.narrowed ? "\u{f0349}" : "\u{f009b}"   // magnify / bell-outline
                font.family: Theme.fontGlyph
                font.pixelSize: 26
                color: Theme.textTertiary
            }
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.narrowed ? "No results" : "No notifications"
            size: 15
            weight: Theme.wSemibold
            color: Theme.textSecondary
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, list.width - 40)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: view.center.query !== "" ? `Nothing matches “${view.center.query}”.`
                : view.filter === "unread" ? "You've seen everything."
                : view.filter === "important" ? "No warnings or alerts."
                : "You're all caught up."
            size: 13
            color: Theme.textTertiary
        }
    }
}
