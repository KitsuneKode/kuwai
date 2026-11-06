// Agent usage limits, grown out of the island (rest on the usage mark, or
// `rice usage`). Tabs: All (every window, the closest to its cap first),
// then one per provider. Each window: who, which window, a small ring for
// what's used (orange past the alert line, red when used up), the
// percentage, and when it resets.
//   Tab / Shift+Tab: the next / previous tab. Esc closes (IslandBar).
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

FocusScope {
    id: usage
    focus: true
    implicitWidth: 420
    implicitHeight: col.implicitHeight + 40

    // Countdowns tick (once a minute) while this is open.
    Binding { target: Limits; property: "panelShown"; value: usage.visible }

    property string tab: "all"
    readonly property var tabs: [{ id: "all", label: "All" }].concat(
        (Limits.providers || []).map(p => ({ id: p.driver || p.label, label: Limits.providerShort(p) })))
    onTabsChanged: if (!tabs.some(t => t.id === tab)) tab = "all"

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
            const i = tabs.findIndex(t => t.id === tab);
            tab = tabs[(i + (e.key === Qt.Key_Backtab ? tabs.length - 1 : 1)) % tabs.length].id;
            e.accepted = true;
        }
    }

    // Used up first (soonest reset first), then the rest by how much is used.
    readonly property var rows: Limits.windows
        .filter(x => tab === "all" || (x.provider.driver || x.provider.label) === tab)
        .slice()
        .sort((a, b) => {
            const ea = a.level === "exhausted", eb = b.level === "exhausted";
            if (ea !== eb) return ea ? -1 : 1;
            if (ea) return (a.window.resetsAt || Infinity) - (b.window.resetsAt || Infinity);
            return b.used - a.used;
        })
    readonly property bool multiAccount: (Limits.providers || []).some(p => (p.accounts || []).length > 1)

    Column {
        id: col
        x: 20; y: 20
        width: usage.width - 40
        spacing: 14

        // ── Title: identity leads, state trails ──────────────────────────
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
                text: Limits.exhausted.length ? Limits.exhausted.length + " used up"
                    : Limits.source === "kittymux" ? "from kittymux" : Limits.source === "t3" ? "from T3 Code" : ""
                size: Theme.tCallout; weight: Theme.wSemibold
                color: Limits.exhausted.length ? Theme.orange : Theme.textTertiary
                font.features: ({ "tnum": 1 })
            }
        }

        Segmented {
            visible: usage.tabs.length > 1
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

        // ── Loading: the rows' own shape ─────────────────────────────────
        Column {
            visible: !Limits.loaded && !Limits.down
            width: parent.width
            spacing: 2
            Repeater {
                model: 2
                Skeleton { width: col.width; height: 46; radius: Theme.r2 }
            }
        }

        // ── Empty ────────────────────────────────────────────────────────
        Label {
            visible: Limits.loaded && usage.rows.length === 0
            width: parent.width
            topPadding: 4; bottomPadding: 4
            text: "No usage data yet · T3 Code or kittymux reports it"
            size: Theme.tBody; color: Theme.textTertiary
        }

        // ── Windows ──────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 2
            Repeater {
                model: ScriptModel { values: usage.rows.slice(0, 8); objectProp: "key" }
                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property color ink: modelData.level === "exhausted" ? Theme.red
                                               : modelData.level === "approaching" ? Theme.orange : Theme.textSecondary
                    width: parent.width
                    height: 46

                    StatRing {
                        id: ring
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        size: 20; stroke: 2.5   // the moment ring's size (IslandRest)
                        value: row.modelData.used
                        color: row.ink
                        text: ""; label: ""
                    }
                    Column {
                        anchors { left: ring.right; leftMargin: 12; right: pct.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Label {
                            width: parent.width; elide: Text.ElideRight
                            text: Limits.windowLabel(row.modelData.window)
                            size: Theme.tBody; weight: Theme.wSemibold
                        }
                        Label {
                            width: parent.width; elide: Text.ElideRight
                            text: Limits.providerShort(row.modelData.provider)
                                + (usage.multiAccount ? " · " + Limits.label(row.modelData.account) : "")
                            size: Theme.tFootnote
                            color: Theme.textTertiary
                        }
                    }
                    Column {
                        id: pct
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Label {
                            anchors.right: parent.right
                            text: row.modelData.level === "exhausted" ? "Used up" : Math.round(row.modelData.used * 100) + "%"
                            size: Theme.tBody; weight: Theme.wSemibold
                            color: row.modelData.level === "" ? Theme.textPrimary : row.ink
                            font.features: ({ "tnum": 1 })
                        }
                        Label {
                            anchors.right: parent.right
                            visible: text !== ""
                            readonly property string resetIn: row.modelData.window.resetsAt ? Limits.resetsIn(row.modelData.window) : ""
                            text: resetIn === "now" ? "resetting" : resetIn ? "resets in " + resetIn : ""
                            size: Theme.tFootnote
                            color: Theme.textTertiary
                            font.features: ({ "tnum": 1 })
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
