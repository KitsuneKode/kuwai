import QtQuick
import qs.config
import qs.components
import qs.services

Rectangle {
    id: card
    property var accounts: Limits.perAccount
    property int max: 3
    readonly property var shown: accounts.filter(a => a.session || a.weekly).slice(0, max)
    visible: shown.length > 0
    implicitHeight: col.implicitHeight + Theme.s3 * 2
    radius: Theme.r3
    color: Theme.card
    border.width: 1; border.color: Theme.cardEdge

    function usedOf(w) { return w ? Math.round((1 - Math.max(0, Math.min(1, w.left))) * 100) : 0; }
    function tileOf(a) { return String(a.brand || "").replace("/brands/", "/brands/tiles/"); }
    function spanOf(w) {
        const d = w ? w.d : 0;
        return !d ? "" : d % 10080 === 0 ? (d / 10080) + "w" : d % 1440 === 0 ? (d / 1440) + "d" : d % 60 === 0 ? (d / 60) + "h" : d + "m";
    }
    function resetOf(w) { return w && w.window && w.window.resetsAt > Limits.now ? "resets " + Limits.resetDay(w.window.resetsAt) : ""; }

    Column {
        id: col
        x: Theme.s3; y: Theme.s3
        width: parent.width - Theme.s3 * 2
        spacing: Theme.s3
        Repeater {
            model: card.shown
            Column {
                id: acc
                required property var modelData
                readonly property var w: modelData.session || modelData.weekly
                readonly property int used: card.usedOf(w)
                readonly property color ink: w && w.out ? Theme.red : w && w.near ? Theme.orange : Theme.textPrimary
                width: col.width
                spacing: 6
                Item {
                    width: parent.width
                    height: Math.max(Theme.sp(20), nameRow.implicitHeight)
                    Row {
                        id: nameRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.s2
                        Image {
                            id: accTile
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18
                            sourceSize: Qt.size(36, 36)
                            source: card.tileOf(acc.modelData)
                            smooth: true; mipmap: true
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: acc.modelData.label
                            size: Theme.tSub; weight: Theme.wSemibold
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!acc.modelData.a && !!acc.modelData.a.plan
                            text: acc.modelData.a ? acc.modelData.a.plan || "" : ""
                            size: Theme.tSub; color: Theme.textTertiary
                        }
                    }
                    Label {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: acc.used + "%"
                        size: Theme.tSub; weight: Theme.wSemibold; rounded: true
                        color: acc.ink
                        tabular: true
                    }
                }
                Item {
                    width: parent.width
                    height: 6
                    Rectangle { anchors.fill: parent; radius: 3; color: Theme.wash(1) }
                    Rectangle {
                        width: Math.max(height, parent.width * acc.used / 100)
                        height: parent.height; radius: 3
                        visible: acc.used > 0
                        color: acc.ink
                        Behavior on width { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.glideMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    }
                    Rectangle {
                        readonly property real e: acc.w ? Limits.elapsed(acc.w.window) : -1
                        visible: e >= 0
                        x: Math.round(parent.width * e) - 1
                        y: -2; width: 2; height: parent.height + 4; radius: 1
                        color: Theme.textSecondary
                    }
                }
                Item {
                    width: parent.width
                    height: metaL.implicitHeight
                    Label {
                        id: metaL
                        text: [card.spanOf(acc.w), card.resetOf(acc.w)].filter(x => x).join(" · ")
                        size: Theme.tFootnote; color: Theme.textTertiary
                        tabular: true
                    }
                    Label {
                        anchors.right: parent.right
                        visible: !!acc.modelData.session && !!acc.modelData.weekly
                        text: "Week " + card.usedOf(acc.modelData.weekly) + "%"
                        size: Theme.tFootnote; color: Theme.textSecondary
                        tabular: true
                    }
                }
            }
        }
    }
    Accessible.role: Accessible.Grouping
    Accessible.name: "Usage: " + shown.map(a => a.label + " " + usedOf(a.session || a.weekly) + " percent used").join(", ")
}
