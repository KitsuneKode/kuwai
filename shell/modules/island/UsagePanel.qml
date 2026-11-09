// Agent usage limits, grown out of the island (rest on the stacked logos, or
// `rice usage`). One card per agent, Claude first, then by urgency: its logo,
// its name and one status ("Out · back in 2h 24m", "82%", "OK"); inside,
// each window as a thin bar that fills on open, with its percent and reset.
// A window shared by two accounts (Antigravity's "Claude & GPT") shows once.
// The header says the one thing that matters: how many are out, and when the
// first comes back.
//   Tab / Shift+Tab: the next / previous tab. Esc closes (IslandBar).
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

FocusScope {
    id: usage
    focus: true
    implicitWidth: 440
    implicitHeight: col.implicitHeight + 40

    // Countdowns tick (once a minute) while this is open.
    Binding { target: Limits; property: "panelShown"; value: usage.visible }

    function pid(p) { return p.driver || p.label; }
    function isClaude(p) { return /claude/i.test(String(p.driver || p.label || "")); }

    property string tab: "all"
    Component.onCompleted: if (Limits.usageTab) { tab = Limits.usageTab; Limits.usageTab = ""; }
    readonly property var tabs: [{ id: "all", label: "All", brand: "" }].concat(
        usage.groups.map(g => ({ id: g.id, label: g.name, brand: g.brand, rank: g.rank })))
    onTabsChanged: if (!tabs.some(t => t.id === tab)) tab = "all"

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
            const i = tabs.findIndex(t => t.id === tab);
            tab = tabs[(i + (e.key === Qt.Key_Backtab ? tabs.length - 1 : 1)) % tabs.length].id;
            e.accepted = true;
        }
    }

    // ── The model: one group per provider ────────────────────────────────
    // rank: 2 out, 1 near the line, 0 fine. Windows deduped by name and
    // reset (a shared quota reported by each account), most used first.
    readonly property var groups: {
        const by = {};
        for (const x of Limits.windows) {
            const id = pid(x.provider);
            const g = by[id] || (by[id] = { id: id, p: x.provider, name: Limits.providerShort(x.provider),
                                            brand: Limits.brandFor(x.provider), tint: Limits.tintFor(x.provider), claude: isClaude(x.provider),
                                            accounts: {}, rows: {}, rank: 0, back: Infinity, top: 0 });
            g.accounts[Limits.label(x.account)] = true;
            const k = Limits.windowLabel(x.window) + "|" + Math.round((x.window.resetsAt || 0) / 600000);
            const r = g.rows[k];
            if (r) { r.shared += 1; continue; }
            g.rows[k] = { key: x.key, label: Limits.windowLabel(x.window), acct: Limits.label(x.account), window: x.window, used: x.used, level: x.level, shared: 1 };
            const rank = x.level === "exhausted" ? 2 : x.level === "approaching" ? 1 : 0;
            g.rank = Math.max(g.rank, rank);
            g.top = Math.max(g.top, x.used);
            if (rank === 2 && x.window.resetsAt) g.back = Math.min(g.back, x.window.resetsAt);
        }
        // Within a card: one section per account (the first account first),
        // and inside it a fixed order, shortest window first (Session, then
        // Weekly). Sorting every row by urgency across accounts read as one
        // shuffled table (Weekly·A, Session·B, Weekly·B, Session·A).
        // Limits first (Session, Weekly, Overall), then each pool together
        // (Gemini 5-hour, Gemini weekly, then Claude & GPT), shortest first.
        const order = (a, b) => Limits.poolOf(a.window).localeCompare(Limits.poolOf(b.window))
            || ((a.window.durationMins || 1e9) - (b.window.durationMins || 1e9)) || a.label.localeCompare(b.label);
        return Object.values(by).map(g => {
            const rows = Object.values(g.rows);
            const accts = {};
            for (const row of rows) (accts[row.acct] = accts[row.acct] || []).push(row);
            const sections = Object.keys(accts).sort((a, b) => a.length - b.length || a.localeCompare(b))
                .map(name => ({ name: name, rows: accts[name].sort(order), state: Limits.stateOf(accts[name]) }));
            // The agent's state: out only when every account is out (a limit
            // spent, or every pool); one empty pool or one spent account of
            // several is "partly". (One empty pool used to mark it all Out.)
            const outs = sections.filter(x => x.state.out);
            const out = outs.length === sections.length;
            const partial = !out && (outs.length > 0 || sections.some(x => x.state.partial));
            const back = Math.min(...rows.filter(x => x.level === "exhausted" && x.window.resetsAt).map(x => x.window.resetsAt), Infinity);
            const why = outs.length && sections.length > 1 ? outs.length + " of " + sections.length + " accounts out"
                : (sections.find(x => x.state.partial) || { state: { pool: "" } }).state.pool + " out";
            return Object.assign(g, { accounts: Object.keys(g.accounts).length, rows: rows, sections: sections,
                                      rank: out ? 2 : partial ? 1.5 : g.rank >= 1 ? 1 : 0, back: back, why: why });
        }).sort((a, b) => (b.claude - a.claude) || (b.rank - a.rank) || (b.top - a.top) || a.name.localeCompare(b.name));
    }
    readonly property var shown: tab === "all" ? groups : groups.filter(g => g.id === tab)
    readonly property int outCount: groups.filter(g => g.rank === 2).length
    readonly property int partCount: groups.filter(g => g.rank === 1.5).length
    readonly property real firstBack: Math.min(...groups.filter(g => g.rank === 2).map(g => g.back), Infinity)

    // "Tue 21:00" a day or more away, else "21:00".
    function at(t) { return !t ? "" : t - Limits.now >= 86400000 ? Qt.formatDateTime(new Date(t), Settings.clock24 ? "ddd HH:mm" : "ddd h:mm ap") : Qt.formatTime(new Date(t), Settings.clock24 ? "HH:mm" : "h:mm ap"); }
    function backIn(at) { return at === Infinity || !at ? "" : at <= Limits.now ? "now" : Limits.duration(at - Limits.now); }
    function tone(level) { return level === "exhausted" ? Theme.red : level === "approaching" ? Theme.orange : Theme.green; }

    Column {
        id: col
        x: 20; y: 20
        width: usage.width - 40
        spacing: 14

        // ── Title: what matters, in one line ─────────────────────────────
        Item {
            width: parent.width
            height: 26
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Usage"
                size: Theme.tTitle3; weight: Theme.wSemibold   // the panels' one title style
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: Limits.loaded
                text: usage.outCount
                    ? usage.outCount + " out" + (usage.partCount ? " · " + usage.partCount + " partly" : "") + (usage.backIn(usage.firstBack) ? " · first back in " + usage.backIn(usage.firstBack) : "")
                    : usage.partCount ? usage.partCount + " partly out · the rest have room" : "All agents have room"
                size: Theme.tFootnote; weight: Theme.wSemibold
                color: usage.outCount ? Theme.orange : Theme.textTertiary
                font.features: ({ "tnum": 1 })
            }
        }

        // Tabs as the agents' logos; the chosen one opens to say its name
        // (six names didn't fit, and logos are what you scan for). A red dot: out.
        Row {
            visible: usage.tabs.length > 2
            spacing: 4
            Repeater {
                model: usage.tabs
                delegate: Rectangle {
                    id: tb
                    required property var modelData
                    readonly property bool on: usage.tab === modelData.id
                    height: 28
                    width: tbRow.implicitWidth + 20
                    radius: 14
                    color: on ? Theme.platter : tbArea.containsMouse ? Theme.platterDim : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                    Behavior on width { NumberAnimation { duration: Theme.reflowMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Row {
                        id: tbRow
                        anchors.centerIn: parent
                        spacing: 6
                        Image {
                            visible: tb.modelData.brand !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14; height: 14
                            source: tb.modelData.brand
                            sourceSize: Qt.size(28, 28)
                            asynchronous: true
                        }
                        Label {
                            visible: tb.on || tb.modelData.brand === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: tb.modelData.label
                            size: Theme.tSub; weight: Theme.wSemibold
                        }
                    }
                    Rectangle {
                        visible: tb.modelData.rank >= 1.5 && !tb.on
                        anchors { right: parent.right; top: parent.top; rightMargin: 5; topMargin: 4 }
                        width: 6; height: 6; radius: 3
                        color: tb.modelData.rank === 2 ? Theme.red : Theme.orange
                    }
                    MouseArea {
                        id: tbArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: usage.tab = tb.modelData.id
                    }
                }
            }
        }

        // ── Error: on the thing that failed, with Retry beside it ─────────
        Rectangle {
            visible: Limits.down
            width: parent.width
            height: 44
            radius: Theme.r2
            color: Qt.alpha(Theme.orange, Theme.tintNotice)
            Label {
                anchors { left: parent.left; leftMargin: 14; right: retry.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: "rice-usage isn't running" + (Limits.loaded ? " · showing the last reading" : "")
                size: Theme.tBody; weight: Theme.wMedium
                color: Theme.orange
            }
            PillButton {
                id: retry
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: "Retry"
                onClicked: Limits.retry()
            }
        }

        // ── Loading: the cards' own shape ────────────────────────────────
        Column {
            visible: !Limits.loaded && !Limits.down
            width: parent.width
            spacing: 8
            Repeater {
                model: 2
                Skeleton { width: col.width; height: 92; radius: Theme.r3 }
            }
        }

        Label {
            visible: Limits.loaded && usage.groups.length === 0
            width: parent.width
            topPadding: 4; bottomPadding: 4
            text: "No usage yet · T3 Code or kittymux reports it"
            size: Theme.tBody; color: Theme.textTertiary
        }

        // ── One card per agent ───────────────────────────────────────────
        Item {
          width: parent.width
          height: flick.height
        Flickable {
            id: flick
            width: parent.width
            height: Math.min(cards.implicitHeight, 470)
            contentHeight: cards.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: cards
                width: flick.width
                spacing: 8
                Repeater {
                    model: ScriptModel { values: usage.shown; objectProp: "id" }
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property var g: modelData
                        width: cards.width
                        height: inner.implicitHeight + 24
                        radius: Theme.r3
                        color: Theme.card
                        border.width: 1
                        border.color: g.rank === 2 ? Qt.alpha(Theme.red, 0.28) : Theme.cardEdge

                        // No entrance of its own: the island's morph carries the cards
                        // in (one entrance per container); only the bars move, filling
                        // with the morph as the one piece of data worth watching.

                        Column {
                            id: inner
                            x: 14; y: 12
                            width: parent.width - 28
                            spacing: 10

                            // Header: logo · name · accounts ……… status
                            Item {
                                width: parent.width
                                height: 22
                                Rectangle {
                                    id: logo
                                    width: 22; height: 22; radius: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.chip
                                    Image {
                                        anchors.centerIn: parent
                                        width: 13; height: 13
                                        source: card.g.brand
                                        sourceSize: Qt.size(26, 26)
                                        asynchronous: true
                                        visible: source != ""
                                    }
                                    Label {
                                        anchors.centerIn: parent
                                        visible: card.g.brand === ""
                                        text: card.g.name.charAt(0)
                                        size: Theme.tFootnote; weight: Theme.wBold
                                    }
                                }
                                Label {
                                    id: pname
                                    anchors { left: logo.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                    text: card.g.name
                                    size: Theme.tCallout; weight: Theme.wSemibold
                                }
                                Label {
                                    anchors { left: pname.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                    visible: card.g.accounts > 1
                                    text: card.g.accounts + " accounts"
                                    size: Theme.tFootnote; color: Theme.textTertiary
                                }
                                // One status: out (and when back), near the line, or fine.
                                Rectangle {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    height: 20
                                    width: status.implicitWidth + 16
                                    radius: 10
                                    color: Qt.alpha(usage.tone(card.g.rank === 2 ? "exhausted" : card.g.rank >= 1 ? "approaching" : ""), 0.14)
                                    Label {
                                        id: status
                                        anchors.centerIn: parent
                                        text: card.g.rank === 2 ? "Out" + (usage.backIn(card.g.back) ? " · back in " + usage.backIn(card.g.back) : "")
                                            : card.g.rank === 1.5 ? card.g.why
                                            : card.g.rank === 1 ? Math.round(card.g.top * 100) + "%" : "OK"
                                        size: Theme.tCaption; weight: Theme.wBold
                                        color: usage.tone(card.g.rank === 2 ? "exhausted" : card.g.rank >= 1 ? "approaching" : "")
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                            }

                            // Windows, per account: a quiet account line (with a hairline
                            // above it from the second on), then its windows:
                            // name ……… what's left, a bar, pace and reset.
                            Repeater {
                              model: card.g.sections
                              delegate: Column {
                                id: sec
                                required property var modelData
                                required property int index
                                width: inner.width
                                spacing: 8
                                Rectangle {
                                    visible: sec.index > 0
                                    width: parent.width; height: 1
                                    color: Theme.cardEdge
                                }
                                Label {
                                    visible: card.g.sections.length > 1
                                    text: sec.modelData.name
                                    size: Theme.tCaption; weight: Theme.wSemibold
                                    color: Theme.textTertiary
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 0.6
                                }
                              Repeater {
                                model: sec.modelData.rows
                                delegate: Column {
                                    id: w
                                    required property var modelData
                                    required property int index
                                    readonly property var r: modelData
                                    width: inner.width
                                    spacing: 5
                                    // T3 Code's reading: what's LEFT, in the agent's colour,
                                    // with a tick where even spending would be.
                                    readonly property int leftPct: Limits.remaining(w.r.window)
                                    readonly property int paceAt: Limits.paceLeft(w.r.window)
                                    readonly property string pace: Limits.pace(w.r.window)
                                    readonly property bool out: w.r.level === "exhausted"
                                    Item {
                                        width: parent.width
                                        height: 16
                                        Label {
                                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                            width: parent.width - pc.width - 8
                                            elide: Text.ElideRight
                                            // Two accounts: say whose ("Weekly · work"), or that it's one shared quota.
                                            text: w.r.label + (w.r.shared > 1 ? "  ·  shared" : "")
                                            size: Theme.tSub; color: Theme.textSecondary
                                        }
                                        Label {
                                            id: pc
                                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                            text: w.out ? "Out" : w.leftPct + "% left"
                                            size: Theme.tSub; weight: Theme.wSemibold
                                            color: w.out ? Theme.red : w.r.level === "approaching" ? Theme.orange : Theme.textPrimary
                                            font.features: ({ "tnum": 1 })
                                        }
                                    }
                                    // The bar drains as you spend; it fills to what's left as the card comes in.
                                    // What's left as a bucket of 20 (5 % each, the last one
                                    // partly full): a quota reads as how many are left, not
                                    // a length to judge. One fill front (k) runs across, so
                                    // the segments light in turn as it passes: a wave, one
                                    // animation, no per-segment timers.
                                    Item {
                                        id: bucket
                                        width: parent.width
                                        height: 8
                                        readonly property int n: 20
                                        readonly property real gap: 2
                                        readonly property real segW: (width - gap * (n - 1)) / n
                                        readonly property color ink: w.r.level === "approaching" ? Theme.orange : card.g.tint
                                        property real k: 0
                                        Component.onCompleted: k = 1
                                        Behavior on k {
                                            enabled: !Theme.reduceMotion
                                            NumberAnimation { duration: Theme.artMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                                        }
                                        Repeater {
                                            model: bucket.n
                                            Rectangle {
                                                required property int index
                                                readonly property real f: Math.max(0, Math.min(1, w.leftPct * bucket.k / (100 / bucket.n) - index))
                                                x: index * (bucket.segW + bucket.gap)
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: bucket.segW; height: 6; radius: 1.5
                                                color: w.out ? Qt.alpha(Theme.red, 0.22) : Theme.track
                                                Rectangle {
                                                    width: parent.width * parent.f; height: parent.height
                                                    radius: parent.radius
                                                    visible: parent.f > 0
                                                    color: bucket.ink
                                                }
                                            }
                                        }
                                        // Pace: where the bar would be if spending were even across the window.
                                        Rectangle {
                                            visible: w.paceAt >= 0 && !w.out
                                            x: Math.max(1, Math.min(parent.width - 3, parent.width * w.paceAt / 100 - 1))
                                            width: 2; height: 8; radius: 1
                                            color: Theme.textPrimary
                                            opacity: 0.85
                                        }
                                    }
                                    Item {
                                        width: parent.width
                                        height: 14
                                        visible: !!w.r.window.resetsAt || w.pace !== ""
                                        Label {
                                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                            visible: w.pace !== "" && !w.out
                                            text: w.pace === "ahead" ? "↗ Ahead of pace" : w.pace === "under" ? "↘ Under pace" : "On pace"
                                            size: Theme.tCaption
                                            color: w.pace === "ahead" ? Theme.orange : Theme.textTertiary
                                        }
                                        Label {
                                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                            readonly property string inS: w.r.window.resetsAt ? Limits.resetsIn(w.r.window) : ""
                                            text: inS === "now" ? "Resetting" : !inS ? "" : (w.out ? "Back " : "Resets ") + usage.at(w.r.window.resetsAt) + " · in " + inS
                                            size: Theme.tCaption
                                            color: w.out ? Qt.alpha(Theme.red, 0.85) : Theme.textTertiary
                                            font.features: ({ "tnum": 1 })
                                        }
                                    }
                                }
                            }
                              }
                            }
                        }
                    }
                }
            }
        }
        // More below: the list fades into the panel (a row cut through its
        // middle read as broken), and a slim scroll hint shows on the edge.
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 36
            visible: flick.contentY < flick.contentHeight - flick.height - 1
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.92) }
            }
        }
        ScrollHint { flickable: flick; anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: -10 } }
        }

    }
}
