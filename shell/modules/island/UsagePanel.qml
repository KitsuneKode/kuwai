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
    readonly property var tabs: [{ id: "all", label: "All" }].concat(
        usage.groups.map(g => ({ id: g.id, label: g.name })))
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
                                            brand: Limits.brandFor(x.provider), claude: isClaude(x.provider),
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
        return Object.values(by).map(g => Object.assign(g, {
            accounts: Object.keys(g.accounts).length,
            rows: Object.values(g.rows).sort((a, b) => (b.level === "exhausted") - (a.level === "exhausted") || b.used - a.used)
        })).sort((a, b) => (b.claude - a.claude) || (b.rank - a.rank) || (b.top - a.top) || a.name.localeCompare(b.name));
    }
    readonly property var shown: tab === "all" ? groups : groups.filter(g => g.id === tab)
    readonly property int outCount: groups.filter(g => g.rank === 2).length
    readonly property real firstBack: Math.min(...groups.filter(g => g.rank === 2).map(g => g.back), Infinity)

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
                size: Theme.tTitle2; weight: Theme.wBold; rounded: true
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: Limits.loaded
                text: usage.outCount
                    ? usage.outCount + " out" + (usage.backIn(usage.firstBack) ? " · first back in " + usage.backIn(usage.firstBack) : "")
                    : "All agents have room"
                size: Theme.tFootnote; weight: Theme.wSemibold
                color: usage.outCount ? Theme.orange : Theme.textTertiary
                font.features: ({ "tnum": 1 })
            }
        }

        Segmented {
            visible: usage.tabs.length > 2
            width: parent.width
            options: usage.tabs
            current: usage.tab
            onPicked: id => usage.tab = id
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

                        // In with the panel, a beat apart (30–80 ms stagger).
                        opacity: 0
                        transform: Translate { id: lift; y: 6 }
                        Component.onCompleted: enter.start()
                        ParallelAnimation {
                            id: enter
                            PauseAnimation { duration: Math.min(card.index, 5) * Theme.revealStepMs }
                            NumberAnimation { target: card; property: "opacity"; to: 1; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                            NumberAnimation { target: lift; property: "y"; to: 0; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                        }

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
                                    color: Qt.alpha(usage.tone(card.g.rank === 2 ? "exhausted" : card.g.rank === 1 ? "approaching" : ""), 0.14)
                                    Label {
                                        id: status
                                        anchors.centerIn: parent
                                        text: card.g.rank === 2 ? "Out" + (usage.backIn(card.g.back) ? " · back in " + usage.backIn(card.g.back) : "")
                                            : card.g.rank === 1 ? Math.round(card.g.top * 100) + "%" : "OK"
                                        size: Theme.tCaption; weight: Theme.wBold
                                        color: usage.tone(card.g.rank === 2 ? "exhausted" : card.g.rank === 1 ? "approaching" : "")
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                            }

                            // Windows: name ……… percent, a bar, when it resets.
                            Repeater {
                                model: card.g.rows
                                delegate: Column {
                                    id: w
                                    required property var modelData
                                    required property int index
                                    readonly property var r: modelData
                                    width: inner.width
                                    spacing: 5
                                    Item {
                                        width: parent.width
                                        height: 16
                                        Label {
                                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                            width: parent.width - pc.width - 8
                                            elide: Text.ElideRight
                                            // Two accounts: say whose ("Weekly · work"), or that it's one shared quota.
                                            text: w.r.label + (w.r.shared > 1 ? "  ·  shared" : card.g.accounts > 1 ? "  ·  " + w.r.acct : "")
                                            size: Theme.tSub; color: Theme.textSecondary
                                        }
                                        Label {
                                            id: pc
                                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                            text: w.r.level === "exhausted" ? "100%" : Math.round(w.r.used * 100) + "%"
                                            size: Theme.tSub; weight: Theme.wSemibold
                                            color: w.r.level === "" ? Theme.textPrimary : usage.tone(w.r.level)
                                            font.features: ({ "tnum": 1 })
                                        }
                                    }
                                    // The bar: fills from empty as the card comes in.
                                    Rectangle {
                                        width: parent.width
                                        height: 4; radius: 2
                                        color: Theme.track
                                        Rectangle {
                                            id: fillBar
                                            height: parent.height; radius: 2
                                            color: w.r.level === "" ? Theme.textSecondary : usage.tone(w.r.level)
                                            property real k: 0
                                            width: Math.max(w.r.used > 0 ? 4 : 0, parent.width * Math.min(1, w.r.used) * k)
                                            Component.onCompleted: k = 1
                                            Behavior on k {
                                                enabled: !Theme.reduceMotion
                                                NumberAnimation { duration: Theme.artMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                                            }
                                        }
                                    }
                                    Label {
                                        visible: text !== ""
                                        readonly property string inS: w.r.window.resetsAt ? Limits.resetsIn(w.r.window) : ""
                                        text: inS === "now" ? "Resetting" : !inS ? "" : w.r.level === "exhausted" ? "Back in " + inS : "Resets in " + inS
                                        size: Theme.tCaption
                                        color: w.r.level === "exhausted" ? Qt.alpha(Theme.red, 0.85) : Theme.textTertiary
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // The way on: every agent and account, in the center's Agents tab.
        PillButton {
            width: parent.width
            text: "All agents"
            onClicked: { Island.close(); Notifs.toggleCenter("agents", "pointer", Island.screen); }
        }
    }
}
