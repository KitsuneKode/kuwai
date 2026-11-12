// The center's Agents tab: kittymux in the rice's glass (see services/Kittymux).
//
//   Needs you   unread inbox events, the ones blocking an agent first:
//               kind chip, the tab it came from, what it said, age
//               (limits count down to their reset). Click jumps to that
//               window; ✕ marks it read.
//   Running     live agent windows; a pulse while the agent is working.
//               Click jumps there.
//   Usage       provider quotas as meters: calm under 70%, orange past it,
//               red at 90%.
//   Recent      closed conversations; click reopens one (kittymux asks
//               before resuming it).
//
// Keyboard (sent here by Center): ↑↓ select, ↵ open, ⌦ mark read.
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: view

    required property var center

    property bool hosting: true
    readonly property bool shown: hosting && center.open && center.tab === "agents"
    Binding { target: Kittymux; property: "watching"; value: view.shown; when: view.hosting }
    Binding { target: Limits; property: "centerShown"; value: view.shown; when: view.hosting }

    function ago(ms) {
        const m = Math.floor((Date.now() - ms) / 60000);
        return m < 1 ? "now" : m < 60 ? m + "m" : m < 1440 ? Math.floor(m / 60) + "h" : Math.floor(m / 1440) + "d";
    }
    function countdown(resetAt) {
        const s = Math.max(0, resetAt - Date.now() / 1000);
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        return s <= 0 ? "reset" : h ? `resets in ${h}h ${m}m` : `resets in ${m}m`;
    }
    readonly property var kinds: ({
        permission: { label: "Permission", tone: Theme.orange },
        question: { label: "Question", tone: Theme.orange },
        limit: { label: "Limit", tone: Theme.yellow },
        done: { label: "Done", tone: Theme.green },
        error: { label: "Error", tone: Theme.red }
    })

    // ── Rows (search narrows them) ───────────────────────────────────────
    readonly property var attention: Kittymux.attention
        .filter(e => center.matchesText([e.agent, e.tab, e.title, e.body, e.kind].join(" ")))
        .map(e => ({ key: "e:" + e.id, type: "event", e: e }))
    readonly property var running: Kittymux.running
        .filter(r => center.matchesText([r.agent, r.title, r.where, r.status].join(" ")))
        .map(r => ({ key: "r:" + r.key, type: "running", r: r }))
    readonly property var recent: Kittymux.recent
        .filter(r => center.matchesText([r.agent, r.title, r.where].join(" ")))
        .map(r => ({ key: "c:" + r.key, type: "recent", r: r }))
    readonly property var usage: (Limits.providers || []).filter(p => center.matchesText([p.label, p.driver, ...p.accounts.map(a => [a.name, a.email, a.plan].join(" "))].join(" ")))
    readonly property var visibleItems: [...attention, ...running, ...recent]

    // ── Selection and hover ──────────────────────────────────────────────
    property string selectedKey: ""
    property Item selectedRow: null
    property Item hoverRow: null
    property bool keyboard: false
    readonly property int selectedIndex: visibleItems.findIndex(x => x.key === selectedKey)

    function setHover(row, on) {
        if (on) { hoverRow = row; keyboard = false; }
        else if (hoverRow === row) hoverRow = null;
    }
    function reset() {
        selectedKey = "";
        selectedRow = null;
        hoverRow = null;
        keyboard = false;
        flick.contentY = 0;
    }
    function selectFirst() { selectedKey = visibleItems.length ? visibleItems[0].key : ""; }
    function move(step) {
        if (!visibleItems.length) return;
        keyboard = true;
        const at = selectedIndex < 0 ? (step > 0 ? -1 : 0) : selectedIndex;
        selectedKey = visibleItems[Math.max(0, Math.min(visibleItems.length - 1, at + step))].key;
    }
    onSelectedRowChanged: if (selectedRow && keyboard) {
        const p = selectedRow.mapToItem(flick.contentItem, 0, 0);
        if (p.y < flick.contentY) flick.contentY = p.y - 8;
        else if (p.y + selectedRow.height > flick.contentY + flick.height)
            flick.contentY = p.y + selectedRow.height - flick.height + 8;
    }

    function open(x) {
        if (x.type === "t3") { T3Code.openThread(x.t.thread); Notifs.setCenter(false); return; }
        if (x.type === "event") Kittymux.jumpEvent(x.e.id);
        else Kittymux.act(x.r.action);
        Notifs.setCenter(false);
    }
    function key(event, queryEmpty) {
        const k = event.key;
        const x = visibleItems[selectedIndex];
        if (k === Qt.Key_Down) move(1);
        else if (k === Qt.Key_Up) move(-1);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (x) open(x); }
        else if ((k === Qt.Key_Delete || (k === Qt.Key_Backspace && queryEmpty)) && x && (x.type === "event" || x.type === "recent")) {
            move(1);
            if (x.type === "event") Kittymux.ack(x.e.id);
            else Kittymux.hideRecent(x.r);
        } else return false;
        return true;
    }

    // ── Layout ───────────────────────────────────────────────────────────
    readonly property real naturalHeight: Math.max(220, column.implicitHeight + 8)
    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentHeight: column.implicitHeight + 8
        boundsBehavior: Flickable.DragAndOvershootBounds

        Column {
            id: column
            width: flick.width
            spacing: 22

            // Not installed / nothing anywhere
            Column {
                visible: !Kittymux.available || (view.visibleItems.length === 0 && view.usage.length === 0)
                width: parent.width
                topPadding: 60
                spacing: 8
                opacity: view.center.revealAt(80)
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 56; height: 56; radius: 28
                    color: Theme.platterDim
                    Image {
                        anchors.centerIn: parent
                        width: 32; height: 32
                        source: Kittymux.icon("kittymux")
                        sourceSize: Qt.size(64, 64)
                        opacity: 0.8
                    }
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: !Kittymux.available ? "kittymux isn't installed" : view.center.query !== "" ? "No results" : "No agents"
                    size: 15
                    weight: Theme.wSemibold
                    color: Theme.textSecondary
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: !Kittymux.available ? "Expected ~/.local/bin/kittymux." : view.center.query !== "" ? `Nothing matches “${view.center.query}”.` : "Start one from kitty and it shows up here."
                    size: 13
                    color: Theme.textTertiary
                }
            }

            // Needs you
            Section {
                title: "Needs you"
                count: view.attention.length
                actionText: "Mark all read"
                onAction: Kittymux.ackAll()
                visible: view.attention.length > 0
                revealDelay: 80
                Repeater {
                    model: ScriptModel { values: view.attention; objectProp: "key" }
                    AgentRow {
                        required property var modelData
                        entry: modelData
                        agent: modelData.e.agent
                        title: Kittymux.clean(modelData.e.tab || modelData.e.title)
                        subtitle: modelData.e.body || modelData.e.title || ""
                        chip: (view.kinds[modelData.e.kind] || {}).label || ""
                        chipTone: (view.kinds[modelData.e.kind] || {}).tone || "transparent"
                        meta: modelData.e.kind === "limit" && modelData.e.reset_at ? view.countdown(modelData.e.reset_at) : view.ago(modelData.e.t * 1000)
                        dismissable: true
                        onDismissed: Kittymux.ack(modelData.e.id)
                    }
                }
            }

            // Running
            Section {
                title: "Running"
                count: view.running.length
                visible: view.running.length > 0
                revealDelay: 120
                Repeater {
                    model: ScriptModel { values: view.running; objectProp: "key" }
                    AgentRow {
                        required property var modelData
                        entry: modelData
                        agent: modelData.r.agent
                        title: modelData.r.title
                        subtitle: [modelData.r.where, modelData.r.status].filter(s => s).join("  ·  ")
                        working: modelData.r.working
                        live: true
                    }
                }
            }

            // T3 Code's threads (services/T3Code): the same rows, so every
            // agent you run is in one place whichever tool started it. Their
            // mark is the agent that runs the thread (Claude, Codex, Cursor…).
            Section {
                title: "T3 Code"
                count: T3Code.items.length
                actionText: "Open T3"
                onAction: { T3Code.focus(); Notifs.setCenter(false); }
                visible: T3Code.items.length > 0
                revealDelay: 140
                Repeater {
                    model: ScriptModel { values: T3Code.items.map(i => ({ key: "t3:" + i.title + ":" + i.provider, type: "t3", t: i })); objectProp: "key" }
                    AgentRow {
                        required property var modelData
                        entry: modelData
                        agent: ({ claudeAgent: "claude" })[String(modelData.t.provider).replace(/_\d+$/, "")] || String(modelData.t.provider).replace(/_\d+$/, "").toLowerCase()
                        title: modelData.t.title || "Untitled thread"
                        subtitle: modelData.t.status === "waiting" ? "Needs you" : modelData.t.status === "running" ? "Working" : "Starting"
                        working: modelData.t.status !== "waiting"
                        live: true
                    }
                }
            }

            // Loading: the shape of agent rows until kittymux first answers.
            Column {
                visible: Kittymux.available && !Kittymux.loaded
                width: parent.width
                spacing: 8
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: parent.width
                        height: 60
                        radius: 18
                        color: Qt.rgba(1, 1, 1, 0.04)
                        Skeleton { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 34; height: 34; radius: 10 }
                        Skeleton { x: 58; y: 15; width: parent.width * (0.55 - parent.index * 0.08); height: 12 }
                        Skeleton { x: 58; y: 35; width: parent.width * 0.3; height: 10 }
                    }
                }
            }

            // Usage: every provider and account, T3 Code's way (UsageCard).
            // Until T3 Code's first snapshot arrives: a card's shape.
            Section {
                title: "Usage"
                visible: view.usage.length > 0 || (Limits.watching && !Limits.loaded)
                revealDelay: 160
                UsageCard { providers: view.usage }
                Rectangle {
                    visible: view.usage.length === 0
                    width: parent.width
                    height: 112
                    radius: 18
                    color: Qt.rgba(1, 1, 1, 0.04)
                    Skeleton { x: 14; y: 14; width: 22; height: 22; radius: 7 }
                    Skeleton { x: 44; y: 19; width: 110; height: 12 }
                    Skeleton { x: 14; y: 50; width: parent.width - 28; height: 8 }
                    Skeleton { x: 14; y: 74; width: parent.width - 28; height: 8 }
                }
            }

            // Recent
            Section {
                title: "Recent"
                visible: view.recent.length > 0
                revealDelay: 200
                Repeater {
                    model: ScriptModel { values: view.recent; objectProp: "key" }
                    AgentRow {
                        required property var modelData
                        entry: modelData
                        agent: modelData.r.agent
                        title: modelData.r.title
                        subtitle: [modelData.r.where, modelData.r.status].filter(s => s).join("  ·  ")
                        trailingGlyph: "\u{f0453}"           // restore
                        dim: true
                        // Not one you'd go back to: × or a swipe, and it stays gone.
                        dismissable: true
                        onDismissed: Kittymux.hideRecent(modelData.r)
                    }
                }
            }
        }

        FluidHighlight {
            parent: flick.contentItem
            target: view.keyboard ? view.selectedRow : (view.hoverRow || null)
            ring: view.keyboard && target !== null
        }
    }

    ScrollHint {
        flickable: flick
        anchors { right: parent.right; rightMargin: -10; top: flick.top; bottom: flick.bottom }
    }

    // ── Pieces ───────────────────────────────────────────────────────────
    component Section: Column {
        id: sec
        property string title
        property int count: 0
        property int revealDelay: 0
        property string actionText
        signal action()
        default property alias rows: body.data
        width: parent ? parent.width : 0
        spacing: 8
        opacity: view.center.revealAt(revealDelay)

        Item {
            width: sec.width
            height: 20
            Text {
                visible: sec.actionText !== ""
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: sec.actionText
                font.family: Theme.fontText
                font.pixelSize: 12
                font.weight: Theme.wMedium
                renderType: Text.NativeRendering
                color: actArea.containsMouse ? Theme.textPrimary : Theme.blue
                MouseArea { id: actArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sec.action() }
            }
        Row {
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Label {
                text: sec.title
                size: 14
                weight: Theme.wSemibold
                color: Theme.textSecondary
            }
            Rectangle {
                visible: sec.count > 1
                anchors.verticalCenter: parent.verticalCenter
                height: 16; radius: 8
                width: countText.implicitWidth + 10
                color: Theme.pill
                Label {
                    id: countText
                    rounded: true
                    anchors.centerIn: parent
                    text: sec.count
                    size: 11
                    weight: Theme.wSemibold
                    font.features: ({ "tnum": 1 })
                    color: Theme.textSecondary
                }
            }
        }
        }
        Column {
            id: body
            width: sec.width
            spacing: 8
        }
    }

    component AgentRow: Item {
        id: row
        property var entry
        property string agent
        property string title
        property string subtitle
        property string chip
        property color chipTone: "transparent"
        property string meta
        property string trailingGlyph
        property bool working: false
        property bool live: false
        property bool dim: false
        property bool dismissable: false
        signal dismissed()

        readonly property bool selected: view.selectedKey === entry.key
        onSelectedChanged: if (selected) view.selectedRow = row
        Component.onDestruction: if (view.hoverRow === row) view.hoverRow = null

        width: parent ? parent.width : 0
        height: 60
        // Dismissable ones swipe away sideways too (SwipeAway, as notifications).
        SwipeAway { id: swipe; span: row.width; enabled: row.dismissable; onLeaving: row.dismissed() }
        transform: Translate { x: swipe.offset }
        opacity: swipe.fade

        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: view.setHover(row, hovered)
        }
        TapHandler { id: tapH; onTapped: view.open(row.entry) }
        // Press feedback, kept tiny: rows are hit often.
        scale: tapH.pressed ? 0.985 : 1
        Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: Qt.rgba(1, 1, 1, 0.065)
            border.width: 1
            border.color: row.chip && row.chipTone.a > 0 && row.chipTone !== Theme.green ? Qt.alpha(row.chipTone, 0.30) : Qt.rgba(1, 1, 1, 0.06)
        }

        // Agent mark (kittymux's own icons); live agents carry a status dot.
        Item {
            id: mark
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 34; height: 34
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: Theme.platter
                opacity: row.dim ? 0.6 : 1
                Image {
                    anchors.centerIn: parent
                    width: 24; height: 24
                    source: Kittymux.icon(row.agent)
                    sourceSize: Qt.size(48, 48)
                    smooth: true
                    mipmap: true
                }
            }
            Rectangle {
                visible: row.live
                width: 12; height: 12; radius: 6
                x: parent.width - 9; y: parent.height - 9
                color: row.working ? Theme.green : Qt.rgba(0.55, 0.55, 0.6, 1)
                border.width: 2
                border.color: Qt.rgba(0.09, 0.09, 0.11, 1)
                // Working: a soft, steady pulse (about once a second).
                SequentialAnimation on opacity {
                    running: row.working && view.shown
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.45; duration: 560; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 560; easing.type: Easing.InOutSine }
                }
            }
        }

        Column {
            anchors { left: mark.right; leftMargin: 12; right: trailing.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 2
            Row {
                width: parent.width
                spacing: 6
                Rectangle {
                    visible: row.chip !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    height: 18; radius: 9
                    width: chipLabel.implicitWidth + 12
                    color: Qt.alpha(row.chipTone, 0.22)
                    Label {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: row.chip
                        size: 11
                        weight: Theme.wSemibold
                        color: row.chipTone
                    }
                }
                Label {
                    width: parent.width - (row.chip ? chipLabel.implicitWidth + 18 : 0)
                    text: view.center.highlight(row.title)
                    textFormat: Text.StyledText
                    elide: Text.ElideRight
                    size: 14
                    weight: Theme.wSemibold
                    color: row.dim ? Theme.textSecondary : Theme.textPrimary
                }
            }
            Label {
                width: parent.width
                visible: text !== ""
                text: view.center.highlight(row.subtitle)
                textFormat: Text.StyledText
                elide: Text.ElideRight
                size: 12
                color: Theme.textTertiary
            }
        }

        Item {
            id: trailing
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: Math.max(metaLabel.implicitWidth, row.trailingGlyph ? 20 : 0, row.dismissable ? 20 : 0)
            height: 20
            Label {
                id: metaLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !(row.dismissable && hover.hovered)
                text: row.meta
                size: 12
                font.features: ({ "tnum": 1 })
                color: Theme.textTertiary
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: row.trailingGlyph !== "" && row.meta === "" && !(row.dismissable && hover.hovered)
                text: row.trailingGlyph
                font.family: Theme.fontGlyph
                font.pixelSize: 15
                color: hover.hovered ? Theme.textPrimary : Theme.textTertiary
            }
            Rectangle {
                visible: row.dismissable && hover.hovered
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20; radius: 10
                color: ackArea.containsMouse ? Theme.pillHover : Theme.pill
                Text {
                    anchors.centerIn: parent
                    text: "\u{f0156}"
                    font.family: Theme.fontGlyph
                    font.pixelSize: 11
                    color: Theme.textPrimary
                }
                MouseArea {
                    id: ackArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.dismissed()
                }
            }
        }
    }
}
