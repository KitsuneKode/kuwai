// Usage limits as T3 Code draws them (apps/web/src/components/usage):
// one card per provider; one row per window pooled across that provider's
// accounts; under it a bar split into one segment per account.
//
//   ◉ Claude Code   Max                         (CL)(K2) 2 accounts
//   5 hour                                 73% left  ↗  ↻ 1h 34m
//   [██████████░░░|░░] [████████████░|░]
//   Weekly                                 56% left      ↻ 5d 5h
//   [██████░░░░|░░░░░] [█████████░░|░░░]
//
// A bar fills with what's LEFT, in the provider's colour; the white tick is
// where even spending would be (the share of the window still to run), so
// fill short of the tick = spending ahead of pace. Single-account bars are
// slim; pooled ones are taller and carry the account and its percentage.
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

Column {
    id: card

    property var providers: []
    width: parent ? parent.width : 0
    spacing: 8

    Repeater {
        model: card.providers

        Rectangle {
            id: block
            required property var modelData
            required property int index
            readonly property var p: modelData
            readonly property var rows: Limits.pool(p)
            readonly property bool pooled: p.accounts.length > 1
            readonly property var plans: [...new Set(p.accounts.map(a => a.plan).filter(x => x))]
            readonly property var notes: p.accounts.map(a => a.note).filter(x => x)

            width: card.width
            height: inner.implicitHeight + 24
            radius: 18
            color: Qt.rgba(1, 1, 1, 0.065)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.06)

            Column {
                id: inner
                x: 14; y: 12
                width: parent.width - 28
                spacing: 10

                // ── Provider ─────────────────────────────────────────────
                Item {
                    width: inner.width
                    height: 22
                    Rectangle {
                        id: mark
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 7
                        color: Qt.alpha(block.p.color, 0.16)
                        Image {
                            anchors.centerIn: parent
                            width: 16; height: 16
                            source: Kittymux.icon(block.p.driver === "cursor" ? "cursor" : block.p.driver)
                            sourceSize: Qt.size(32, 32)
                            smooth: true
                            mipmap: true
                        }
                    }
                    Label {
                        id: name
                        anchors { left: mark.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        text: block.p.label
                        size: 13
                        weight: Theme.wSemibold
                    }
                    Rectangle {
                        visible: block.plans.length > 0
                        x: name.x + name.implicitWidth + 8
                        anchors.verticalCenter: parent.verticalCenter
                        height: 16; radius: 8
                        width: planLabel.implicitWidth + 12
                        color: Qt.rgba(1, 1, 1, 0.08)
                        Label {
                            id: planLabel
                            anchors.centerIn: parent
                            text: block.plans.map(x => x.charAt(0).toUpperCase() + x.slice(1)).join(" · ")
                            size: 11
                            weight: Theme.wMedium
                            color: Theme.textSecondary
                        }
                    }
                    // Accounts: overlapping initials, then how many.
                    Label {
                        id: count
                        visible: block.pooled
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: block.p.accounts.length + " accounts"
                        size: 11
                        color: Theme.textTertiary
                    }
                    Repeater {
                        model: block.pooled ? block.p.accounts.slice(0, 4) : []
                        AccountChip {
                            required property var modelData
                            required property int index
                            account: modelData
                            anchors.verticalCenter: parent.verticalCenter
                            x: count.x - 8 - (Math.min(4, block.p.accounts.length) - index) * 13 - 3
                            z: 10 - index
                        }
                    }
                }

                // ── Windows ──────────────────────────────────────────────
                Repeater {
                    model: block.rows
                    Column {
                        id: win
                        required property var modelData
                        readonly property var r: modelData
                        readonly property color tone: r.remaining <= 10 ? Theme.red : r.remaining <= 25 ? Theme.orange : Theme.textPrimary
                        width: inner.width
                        spacing: 5

                        Item {
                            width: win.width
                            height: 16
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: win.r.label
                                size: 12
                                color: Theme.textSecondary
                            }
                            Label {
                                id: resets
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                visible: text !== ""
                                text: win.r.resetsIn ? "↻ " + win.r.resetsIn : ""
                                size: 11
                                rounded: true
                                font.features: ({ "tnum": 1 })
                                color: Theme.textTertiary
                            }
                            Text {
                                id: paceGlyph
                                anchors { right: resets.visible ? resets.left : parent.right; rightMargin: resets.visible ? 8 : 0; verticalCenter: parent.verticalCenter }
                                visible: win.r.pace !== ""
                                width: visible ? implicitWidth : 0
                                // trending up / gauge / trending down
                                text: ({ ahead: "\u{f0535}", on: "\u{f029a}", under: "\u{f0533}" })[win.r.pace] || ""
                                font.family: Theme.fontGlyph
                                font.pixelSize: 13
                                color: win.r.pace === "ahead" ? Theme.orange : Theme.textTertiary
                            }
                            Label {
                                anchors { right: paceGlyph.visible ? paceGlyph.left : resets.visible ? resets.left : parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                text: win.r.remaining + "% left"
                                size: 12
                                rounded: true
                                weight: Theme.wSemibold
                                font.features: ({ "tnum": 1 })
                                color: win.tone
                            }
                        }

                        // One segment per account, side by side.
                        Item {
                            id: bar
                            readonly property int n: win.r.members.length
                            readonly property real gap: 4
                            readonly property real segW: (width - gap * (n - 1)) / Math.max(1, n)
                            width: win.width
                            height: block.pooled ? 22 : 8
                            Repeater {
                                model: win.r.members
                                Segment {
                                    required property var modelData
                                    required property int index
                                    member: modelData
                                    tint: block.p.color
                                    labelled: block.pooled
                                    x: index * (bar.segW + bar.gap)
                                    width: bar.segW
                                    height: bar.height
                                }
                            }
                        }
                    }
                }

                Label {
                    visible: block.notes.length > 0
                    width: inner.width
                    elide: Text.ElideRight
                    text: block.notes.join("  ·  ")
                    size: 11
                    color: Theme.textTertiary
                }
            }
        }
    }

    // ── Pieces ───────────────────────────────────────────────────────────
    component AccountChip: Rectangle {
        property var account
        readonly property int h: Limits.hue(account)
        width: 18; height: 18; radius: 9
        color: Qt.hsla(h / 360, 0.55, 0.78, 1)
        border.width: 1.5
        border.color: Qt.rgba(0.13, 0.13, 0.16, 1)
        Label {
            anchors.centerIn: parent
            text: Limits.initials(parent.account)
            size: 9
            weight: Theme.wBold
            rounded: true
            color: Qt.hsla(parent.h / 360, 0.5, 0.26, 1)
        }
    }

    component Segment: Item {
        id: seg
        property var member
        property color tint
        property bool labelled: false
        readonly property int share: Limits.remaining(member.window)
        readonly property int paceAt: Limits.paceLeft(member.window)

        Rectangle {
            id: track
            anchors.fill: parent
            radius: seg.labelled ? 7 : height / 2
            color: Theme.track
            clip: false
        }
        // What's left. Pooled bars sit the label on a quieter fill.
        Rectangle {
            height: parent.height
            radius: track.radius
            width: seg.share <= 0 ? 0 : Math.max(height, parent.width * seg.share / 100)
            color: seg.tint
            opacity: seg.labelled ? 0.42 : 0.95
            Behavior on width { NumberAnimation { duration: Theme.reflowMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
        }
        // Even pace: where the fill would be if spending kept time.
        Rectangle {
            visible: seg.paceAt >= 0 && parent.width >= 6
            x: Math.max(2, Math.min(parent.width - 4, parent.width * seg.paceAt / 100 - 1))
            y: seg.labelled ? 3 : -2
            width: 2
            height: parent.height - 2 * y
            radius: 1
            color: Theme.textPrimary
            opacity: 0.9
        }
        Row {
            visible: seg.labelled && seg.width > 64
            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
            spacing: 5
            AccountChip { account: seg.member.account; anchors.verticalCenter: parent.verticalCenter; border.width: 0; width: 15; height: 15; radius: 7.5 }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Limits.remaining(seg.member.window) + "%"
                size: 11
                rounded: true
                weight: Theme.wSemibold
                font.features: ({ "tnum": 1 })
            }
        }
    }
}
