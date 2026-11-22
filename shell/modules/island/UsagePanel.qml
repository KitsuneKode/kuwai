// Agent usage limits, grown out of the island (rest on the stacked logos, or
// `kuwai usage`). One card per agent, Claude first, then by urgency: its logo,
// its name and one status ("Out · back in 2h 24m", "82%", "OK"); inside,
// each window as a thin bar that fills on open, with its percent and reset.
// A window shared by two accounts (Antigravity's "Claude & GPT") shows once.
// The header says the one thing that matters: how many are out, and when the
// first comes back.
//   Tab / Shift+Tab: the next / previous tab (Spend, Tokens: the period). Ctrl+Tab: Limits, Spend, Tokens. Esc closes.
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services
// Quickshell reloads on QML changes, not on the JS modules they import: after
// changing usage.mjs, save a QML file too.
import "../../services/usage.mjs" as Usage
import qs.components.ui as Ui

FocusScope {
    id: usage
    focus: true
    implicitWidth: Theme.panelS
    implicitHeight: col.implicitHeight + 40
    // The list scrolls past what the island leaves it: the tallest a panel may
    // be (IslandBar: at most 640, the screen less 24; less its 40 of margin and
    // the 34 of the section strip), less this panel's own rows around the list.
    // It was a fixed 470, which with the title and tabs came to 592 against a
    // ceiling of 566 on a 1080-high screen: the last card ran under the edge.
    readonly property real ceiling: Math.min(Theme.panelMaxH, Theme.screenSize(Screen, "height", 1080) - 24) - 40 - 34
    readonly property bool hasTabs: tabs.length > 2
    readonly property bool hasFoot: Limits.loaded && groups.length > 0
    // (By the rows' own heights: they grow with the Text size; fixed numbers
    // let the panel outgrow the island at 200 %.)
    readonly property real listMax: Math.max(120, ceiling - 40 - head.height - col.spacing - viewSeg.height - col.spacing
        - (hasTabs ? tabsRow.height + col.spacing : 0) - (hasFoot ? foot.height + col.spacing : 0) - (Limits.down ? downBox.height + col.spacing : 0))

    // Countdowns tick (once a minute) while this is open.
    Binding { target: Limits; property: "panelShown"; value: usage.visible }
    // What each provider spent, from this machine's logs (services/Spend): read
    // only while this shows.
    Binding { target: Spend; property: "wanted"; value: usage.visible }

    function pid(p) { return p.driver || p.label; }
    function isClaude(p) { return /claude/i.test(String(p.driver || p.label || "")); }

    property string tab: "all"
    property string view: "limits"
    property alias spendData: spendView.doc
    readonly property bool limitsView: view === "limits"
    Component.onCompleted: {
        if (Limits.usageTab === "spend" || Limits.usageTab === "tokens") view = Limits.usageTab;
        else if (Limits.usageTab) tab = Limits.usageTab;
        Limits.usageTab = "";
    }
    readonly property var tabs: [{ id: "all", label: "All", brand: "" }].concat(
        usage.groups.map(g => ({ id: g.id, label: g.name, brand: g.brand, rank: g.rank })))
    onTabsChanged: if (!tabs.some(t => t.id === tab)) tab = "all"

    Keys.onPressed: e => {
        if ((e.modifiers & Qt.ControlModifier) && (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab)) {
            const v = ["limits", "spend", "tokens"], i = v.indexOf(view);
            view = v[(i + (e.key === Qt.Key_Backtab ? 2 : 1)) % 3];
            e.accepted = true;
            return;
        }
        if (!limitsView && (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab || e.key === Qt.Key_Left || e.key === Qt.Key_Right)) {
            spendView.step(e.key === Qt.Key_Backtab || e.key === Qt.Key_Left ? -1 : 1);
            e.accepted = true;
            return;
        }
        if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
            const i = tabs.findIndex(t => t.id === tab);
            tab = tabs[(i + (e.key === Qt.Key_Backtab ? tabs.length - 1 : 1)) % tabs.length].id;
            e.accepted = true;
        }
    }

    // ── The model: one group per provider ────────────────────────────────
    // rank: 2 out, 1 near the line, 0 fine. One section per account.
    readonly property var groups: {
        const by = {};
        for (const x of Limits.windows) {
            const id = pid(x.provider);
            const g = by[id] || (by[id] = { id: id, p: x.provider, name: Limits.providerShort(x.provider),
                                            brand: Limits.brandFor(x.provider), tint: Limits.tintFor(x.provider), claude: isClaude(x.provider),
                                            accounts: {}, rows: {}, rank: 0, back: Infinity, top: 0 });
            // Per account (its key), each account's windows once: keyed by
            // the account's name, T3's two "Cursor" accounts were one
            // section with every row twice.
            const acct = Limits.accountLabel(x.provider, x.account);
            g.accounts[acct] = true;
            const k = acct + "|" + (x.window.id || Limits.windowLabel(x.window));
            if (g.rows[k]) continue;
            g.rows[k] = { key: x.key, label: Limits.windowLabel(x.window), acct: acct, window: x.window, used: x.used, level: x.level,
                          plan: x.account.plan || "", checkedAt: x.account.checkedAt || 0 };
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
                .map(name => ({ name: name, rows: accts[name].sort(order), state: Limits.stateOf(accts[name]),
                                plan: accts[name][0].plan, checkedAt: accts[name][0].checkedAt }));
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
    function at(t) { return !t ? "" : t - Limits.now >= 86400000 ? Dates.weekdayTime(t) : Dates.time(t); }
    function backIn(at) { return at === Infinity || !at ? "" : at <= Limits.now ? "now" : Limits.duration(at - Limits.now); }
    function tone(level) { return level === "exhausted" ? Theme.red : level === "approaching" ? Theme.orange : Theme.green; }

    Column {
        id: col
        x: 20; y: 20
        width: usage.width - 40
        spacing: 14

        // ── Title: what matters, in one line ─────────────────────────────
        // Where the summary doesn't fit beside the title (a large Text size), it
        // goes under it.
        Item {
            id: head
            width: parent.width
            readonly property bool stack: summary.visible && headTitle.implicitWidth + Theme.s3 + summary.implicitWidth > width
            height: stack ? headTitle.implicitHeight + 2 + summary.implicitHeight : Math.max(Theme.sp(26), headTitle.implicitHeight)
            Label {
                id: headTitle
                y: head.stack ? 0 : (head.height - implicitHeight) / 2
                text: "Usage"
                size: Theme.tTitle3; weight: Theme.wSemibold   // the panels' one title style
            }
            Label {
                id: summary
                x: head.stack ? 0 : head.width - implicitWidth
                y: head.stack ? headTitle.implicitHeight + 2 : (head.height - implicitHeight) / 2
                width: head.stack ? head.width : implicitWidth
                wrapMode: head.stack ? Text.Wrap : Text.NoWrap
                visible: Limits.loaded && usage.limitsView
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
        Segmented {
            id: viewSeg
            width: parent.width
            options: [{ id: "limits", label: "Limits" }, { id: "spend", label: "Spend" }, { id: "tokens", label: "Tokens" }]
            current: usage.view
            onPicked: id => usage.view = id
        }

        SpendView {
            id: spendView
            visible: !usage.limitsView
            width: parent.width
            metric: usage.view === "tokens" ? "tokens" : "cost"
            maxH: Math.max(120, usage.ceiling - 40 - head.height - viewSeg.height - 3 * col.spacing - Theme.sp(36) - Theme.s3)
        }

        Row {
            id: tabsRow
            visible: usage.limitsView && usage.hasTabs
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
                    Accessible.role: Accessible.PageTab
                    Accessible.name: tb.modelData.label
                    Accessible.description: tb.modelData.rank === 2 ? "Out" : tb.modelData.rank >= 1.5 ? "Near its limit" : ""
                    Accessible.selected: tb.on
                    Accessible.onPressAction: usage.tab = tb.modelData.id
                }
            }
        }

        // ── Error: on the thing that failed, with Retry beside it ─────────
        Rectangle {
            id: downBox
            visible: usage.limitsView && Limits.down
            width: parent.width
            // Its line wraps (the row grows) rather than lose its end beside Retry at a large Text size.
            height: Math.max(44, downLine.implicitHeight + 2 * Theme.s3)
            radius: Theme.r2
            color: Qt.alpha(Theme.orange, Theme.tintNotice)
            Label {
                id: downLine
                anchors { left: parent.left; leftMargin: 14; right: retry.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: Limits.loaded ? "Not updating · showing the last reading" : "Usage can't be read right now"
                size: Theme.tBody; weight: Theme.wMedium
                color: Theme.orange
            }
            Ui.Button {
                id: retry
                height: Theme.sp(30); size: Theme.tSub
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: "Retry"
                onClicked: Limits.retry()
            }
        }

        // ── Loading: the cards' own shape ────────────────────────────────
        Column {
            visible: usage.limitsView && !Limits.loaded && !Limits.down
            width: parent.width
            spacing: 8
            Repeater {
                model: 2
                Skeleton { width: col.width; height: 92; radius: Theme.r3 }
            }
        }

        Label {
            visible: usage.limitsView && Limits.loaded && usage.groups.length === 0
            width: parent.width
            topPadding: 4; bottomPadding: 4
            text: "No usage yet · T3 Code or kittymux reports it"
            size: Theme.tBody; color: Theme.textTertiary
        }

        // ── One card per agent ───────────────────────────────────────────
        Item {
          id: listWrap
          visible: usage.limitsView
          width: parent.width
          height: flick.height
        Flickable {
            id: flick
            width: parent.width
            height: Math.min(cards.implicitHeight, usage.listMax)
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
                        // The widest window name in this card: every bar starts at the
                        // same place ("Session", "Weekly" and "Weekly · Fable" each
                        // started theirs somewhere else).
                        property real labelW: 0
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

                            // Header: logo · name · accounts ……… status. Where the
                            // status doesn't fit on that line it goes under the name.
                            Item {
                                id: cardHead
                                width: parent.width
                                readonly property bool stack: logo.width + 10 + pname.implicitWidth + 6 + pcount.implicitWidth + Theme.s3 + pchip.width > width
                                readonly property real line: Math.max(22, pname.implicitHeight)
                                height: stack ? line + 4 + pchip.height : line
                                Rectangle {
                                    id: logo
                                    width: 22; height: 22; radius: 11
                                    y: (cardHead.line - height) / 2
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
                                    anchors { left: logo.right; leftMargin: 10 }
                                    y: (cardHead.line - implicitHeight) / 2
                                    text: card.g.name
                                    size: Theme.tCallout; weight: Theme.wSemibold
                                }
                                Label {
                                    id: pcount
                                    anchors { left: pname.right; leftMargin: 6; baseline: pname.baseline }
                                    visible: text !== ""
                                    width: Math.min(implicitWidth, Math.max(0, cardHead.width - x))
                                    elide: Text.ElideRight
                                    text: card.g.accounts > 1 ? card.g.accounts + " accounts" : (card.g.sections[0] && card.g.sections[0].plan) || ""
                                    size: Theme.tFootnote; color: Theme.textTertiary
                                }
                                // One status: out (and when back), near the line, or fine.
                                Rectangle {
                                    id: pchip
                                    x: cardHead.stack ? pname.x : cardHead.width - width
                                    y: cardHead.stack ? cardHead.line + 4 : (cardHead.line - height) / 2
                                    height: Math.max(20, status.implicitHeight + Theme.s1)
                                    width: status.implicitWidth + 16
                                    radius: 10
                                    color: Qt.alpha(usage.tone(card.g.rank === 2 ? "exhausted" : card.g.rank >= 1 ? "approaching" : ""), 0.14)
                                    Label {
                                        id: status
                                        anchors.centerIn: parent
                                        text: card.g.rank === 2 ? "Out" + (usage.backIn(card.g.back) ? " · back in " + usage.backIn(card.g.back) : "")
                                            : card.g.rank === 1.5 ? card.g.why
                                            : card.g.rank === 1 ? Math.max(0, 100 - Math.round(card.g.top * 100)) + "% left" : "OK"   // the rows' own unit (it said "89%", used, above rows saying "11% left")
                                        size: Theme.tCaption; weight: Theme.wBold
                                        // Out: red for text (red itself on its own wash read 4.3:1).
                                        color: card.g.rank === 2 ? Theme.redText : usage.tone(card.g.rank >= 1 ? "approaching" : "")
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                            }

                            // What it spent (services/Spend): tokens today, and an
                            // estimate at list prices, from this machine's own logs.
                            Label {
                                id: spendLine
                                readonly property string said: Spend.line(card.g.id)
                                visible: said !== ""
                                width: parent.width
                                wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                                text: said
                                size: Theme.tFootnote
                                color: Theme.textTertiary
                                font.features: ({ "tnum": 1 })
                                HoverHandler { id: spendHover }
                                Tip {
                                    shown: spendHover.hovered
                                    below: true
                                    text: "From the logs " + card.g.name + " keeps on this machine. Money is an estimate at list prices"
                                        + (Spend.pricesAsOf ? " (as of " + Spend.pricesAsOf + ")" : "") + "; a subscription doesn't pay these."
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
                                // Whose windows these are, and how old the reading is when
                                // that is worth knowing ("as of 45m ago": T3 Code asks each
                                // provider on its own schedule, so one can be far behind).
                                Item {
                                    id: secHead
                                    // By its own age only: that the whole reading is a kept one
                                    // is the footer's line, said once, not once per account.
                                    readonly property var fresh: Usage.freshness(sec.modelData.checkedAt, Limits.now, "")
                                    readonly property bool behind: fresh.known && fresh.stale
                                        && Math.abs((sec.modelData.checkedAt || 0) - Limits.checkedAt) > 5 * 60000
                                    readonly property string who: (card.g.sections.length > 1 ? sec.modelData.name : "")
                                        + (card.g.sections.length > 1 && sec.modelData.plan ? " · " + sec.modelData.plan : "")
                                    visible: who !== "" || behind
                                    width: parent.width
                                    height: 14
                                    Label {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        text: secHead.who
                                        size: Theme.tCaption; weight: Theme.wSemibold
                                        color: Theme.textTertiary
                                        font.capitalization: Font.AllUppercase
                                        font.letterSpacing: 0.6
                                    }
                                    Label {
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        visible: secHead.behind
                                        text: "as of " + secHead.fresh.age
                                        size: Theme.tCaption
                                        color: secHead.fresh.old ? Theme.orange : Theme.textTertiary
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                              Repeater {
                                model: sec.modelData.rows
                                // One line per window: what it is, how much is left (the
                                // bar and the number), when it comes back. A second line
                                // only when there is news: it is out, or at the rate so
                                // far it will be before it resets. (Each window used to
                                // take three lines and say "On pace" when nothing was up;
                                // three accounts ran off the bottom of the island.)
                                delegate: Column {
                                    id: w
                                    required property var modelData
                                    required property int index
                                    readonly property var r: modelData
                                    width: inner.width
                                    spacing: 3
                                    readonly property int leftPct: Limits.remaining(w.r.window)
                                    readonly property int paceAt: Limits.paceLeft(w.r.window)
                                    readonly property bool out: w.r.level === "exhausted"
                                    readonly property bool near: w.r.level === "approaching"
                                    readonly property var forecast: w.out ? null : Usage.runsOut(w.r.window, Limits.now)
                                    readonly property string inS: w.r.window.resetsAt ? Limits.resetsIn(w.r.window) : ""
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: w.r.label + ": " + (w.out ? "out" : w.leftPct + " percent left")
                                        + (w.inS && w.inS !== "now" ? ", resets in " + w.inS : "") + (note.visible ? ". " + note.text : "")
                                    // Its height from its text; at a large Text size the bar
                                    // goes under the name and the numbers (it was a fixed
                                    // 18 px line, and rows ran into each other at 200 %).
                                    Item {
                                        id: line
                                        width: parent.width
                                        readonly property bool stack: Theme.textScale >= 1.5
                                        readonly property real first: Math.max(18, name.implicitHeight, pc.implicitHeight)
                                        height: stack ? first + 6 + bucket.height : first
                                        Label {
                                            id: name
                                            anchors.left: parent.left
                                            y: (line.first - implicitHeight) / 2
                                            // As wide as the longest label needs, up to 40 % of the row
                                            // ("Claude & GPT (shared) · 5-hour" is cut, with the whole of
                                            // it in the tip); "Session" and "Weekly" leave the bar its room.
                                            width: line.stack ? Math.max(0, pc.x - 8) : Math.min(Math.max(implicitWidth, card.labelW), Math.round(parent.width * 0.4))
                                            onImplicitWidthChanged: card.labelW = Math.max(card.labelW, implicitWidth)
                                            Component.onCompleted: card.labelW = Math.max(card.labelW, implicitWidth)
                                            elide: Text.ElideRight
                                            text: w.r.label
                                            size: Theme.tSub; color: Theme.textSecondary
                                        }
                                        Label {
                                            id: back
                                            anchors.right: parent.right
                                            y: (line.first - implicitHeight) / 2
                                            width: Theme.sp(58)
                                            horizontalAlignment: Text.AlignRight
                                            text: w.inS === "now" ? "resetting" : w.inS
                                            size: Theme.tCaption
                                            color: w.out ? Theme.redText : Theme.textTertiary      // red for text on dark (85 % red read 4.0:1)
                                            font.features: ({ "tnum": 1 })
                                        }
                                        Label {
                                            id: pc
                                            anchors { right: back.left; rightMargin: 6 }
                                            y: (line.first - implicitHeight) / 2
                                            width: Theme.sp(56)
                                            horizontalAlignment: Text.AlignRight
                                            text: w.out ? "Out" : w.leftPct + "% left"
                                            size: Theme.tSub; weight: Theme.wSemibold
                                            color: w.out ? Theme.red : w.near || w.forecast ? Theme.orange : Theme.textPrimary
                                            font.features: ({ "tnum": 1 })
                                        }
                                        // The bar drains as you spend. Its colour is its state, not
                                        // the agent's brand: Claude's own orange made a full, healthy
                                        // bar look like a warning, and orange means "near the line"
                                        // everywhere else in the shell.
                                        Item {
                                            id: bucket
                                            x: line.stack ? 0 : name.width + 10
                                            y: line.stack ? line.first + 6 : (line.first - height) / 2
                                            width: line.stack ? line.width : Math.max(0, pc.x - 8 - x)
                                            height: 8
                                            readonly property color ink: w.near || w.forecast ? Theme.orange : Qt.alpha(Theme.textPrimary, 0.72)
                                            property real k: 0
                                            Component.onCompleted: k = 1
                                            Behavior on k {
                                                enabled: !Theme.reduceMotion
                                                NumberAnimation { duration: Theme.artMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                                            }
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width; height: 5; radius: 2.5
                                                color: w.out ? Qt.alpha(Theme.red, 0.22) : Theme.track
                                                Rectangle {
                                                    visible: width > 0.5
                                                    width: parent.width * Math.max(0, Math.min(1, w.leftPct / 100)) * bucket.k
                                                    height: parent.height; radius: parent.radius
                                                    color: bucket.ink
                                                    Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                                                }
                                            }
                                            // Where the bar would be if spending were even across the
                                            // window: left of the tick, you are spending faster than that.
                                            Rectangle {
                                                visible: w.paceAt >= 0 && !w.out
                                                x: Math.max(1, Math.min(parent.width - 3, parent.width * w.paceAt / 100 - 1))
                                                width: 2; height: 8; radius: 1
                                                color: Theme.textPrimary
                                                opacity: 0.55
                                            }
                                        }
                                        HoverHandler { id: lineHover }
                                        Tip {
                                            shown: lineHover.hovered
                                            below: true
                                            text: w.r.label
                                                + (w.r.window.resetsAt ? "\n" + (w.out ? "Back " : "Resets ") + usage.at(w.r.window.resetsAt) : "")
                                                + "\n" + (100 - w.leftPct) + "% used"
                                                + (w.paceAt >= 0 ? " · " + (100 - w.paceAt) + "% of its time gone (the tick)" : "")
                                        }
                                    }
                                    Label {
                                        id: note
                                        visible: w.out || !!w.forecast
                                        width: parent.width
                                        wrapMode: Text.Wrap
                                        text: w.out ? (w.r.window.resetsAt ? "Back " + usage.at(w.r.window.resetsAt) : "Spent")
                                            : w.forecast ? "At this rate it runs out in " + Usage.span(w.forecast.inMs) + ", " + Usage.span(w.forecast.earlyMs) + " before it resets" : ""
                                        size: Theme.tCaption
                                        color: w.out ? Theme.redText : Theme.orange
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
        // More below: the list fades out (a row cut through its middle read as
        // broken), and a slim scroll hint shows on the edge.
        ScrollFade { flickable: flick }
        ScrollHint { flickable: flick; anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: -10 } }
        }

        // ── Where the numbers come from, and how old they are ────────────
        // A reading is pushed as it changes (nothing to refresh by hand), so
        // what is worth saying is its source and, when it isn't live, its age.
        Item {
            id: foot
            visible: usage.limitsView && usage.hasFoot
            width: parent.width
            height: 14
            readonly property var fresh: Usage.freshness(Limits.checkedAt, Limits.now, Limits.source)
            readonly property bool live: Limits.source === "t3" && !Limits.down && !(fresh.known && fresh.stale)
            readonly property bool caution: Limits.down || fresh.old
            Rectangle {
                id: dot
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: 6; height: 6; radius: 3
                color: foot.live ? Theme.green : foot.caution ? Theme.orange : Theme.textTertiary
            }
            Label {
                anchors { left: dot.right; leftMargin: 6; right: parent.right; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: Limits.source === "t3-cached" ? "T3 Code is closed · its last reading" + (foot.fresh.known ? ", " + foot.fresh.age : "")
                    : (foot.live ? "Live from " : "From ") + (Usage.sourceName(Limits.source) || "the last reading")
                      + (foot.fresh.known ? " · checked " + foot.fresh.age : "")
                size: Theme.tCaption
                color: foot.caution ? Theme.orange : Theme.textTertiary
                font.features: ({ "tnum": 1 })
            }
        }
    }
}
