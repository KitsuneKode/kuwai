// Updates waiting and a warning, as marks (components/RestMark): in the
// rest row (IslandRest), or in a pill of their own (IslandSplit).
import QtQuick
import qs.config
import qs.components
import qs.services

Row {
    id: sys
    // Passed in: the island this sits in (its screen, for previews).
    property var bar
    // While a live activity has the stage only a warning stays; update
    // news waits (it sat beside a timer's countdown).
    property bool quiet: false
    // An update running while another live activity (a timer, dictation)
    // holds the stage: it still shows, as a ring with its percent. The
    // notch said nothing while the panel showed Build / Install.
    property bool updateOffStage: false
    spacing: 2
    // From the data, not the children's `visible`: a hidden parent makes
    // every child report invisible, so `any` could never turn on.
    readonly property bool any: (Updates.fresh && !Updates.running && !quiet) || Alerts.active.length > 0 || Limits.markShown || updateOffStage
    readonly property bool hovered: upd.hovered || warn.hovered || lim.hovered || updRun.hovered
    RestMark {
        id: updRun
        visible: sys.updateOffStage
        anchors.verticalCenter: parent.verticalCenter
        glyph: "\u{f06b0}"
        value: String(Math.round(Math.max(0, Math.min(0.99, Updates.progress)) * 100))
        ring: "spin"
        tone: Theme.accent
        previews: true
        onPreviewRequested: if (Island.panel === "" && sys.bar) Island.preview("updates", sys.bar.screenName)
        onClicked: Island.open("updates", sys.bar ? sys.bar.screenName : "", "pointer", "island")
    }
    RestMark {
        id: upd
        // Only while this set is new to you: once you've looked, it steps
        // back (the hover view and Super+Ctrl+Shift+U still have it).
        visible: Updates.fresh && !Updates.running && !sys.quiet
        anchors.verticalCenter: parent.verticalCenter
        glyph: "\u{f06b0}"
        value: Updates.total > 9 ? "9+" : String(Updates.total)
        previews: true
        onPreviewRequested: if (Island.panel === "" && sys.bar) Island.preview("updates", sys.bar.screenName)
        onClicked: Island.open("updates", sys.bar ? sys.bar.screenName : "", "pointer", "island")
    }
    RestMark {
        id: warn
        visible: Alerts.active.length > 0
        anchors.verticalCenter: parent.verticalCenter
        glyph: Alerts.active.length ? Alerts.active[0].glyph : ""
        // The number that matters (96°, 91 %), when the title has one.
        value: Alerts.active.length ? ((Alerts.active[0].title.match(/\d+\s*[%°]/) || [""])[0]).replace(/\s+/g, "") : ""
        tone: Alerts.active.length && Alerts.active[0].level === "crit" ? Theme.red : Theme.orange
        tip: Alerts.active.length ? Alerts.active.map(a => a.title).join(" · ") + " · click for System" : ""
        onClicked: Island.open("system", sys.bar ? sys.bar.screenName : "", "pointer", "island")
    }
    // An agent's usage window used up (services/Limits): the gauge and the
    // soonest reset ("3d") in a solid orange ring, until it resets. Like
    // a warning it stays while a live activity has the stage. Rest on
    // it: the Usage panel.
    // Back soon (Limits.backSoon): an out agent resets within 15 min.
    // Its logo inside a ring that drains to the reset, and the minutes
    // left. Out for days says nothing at rest: you can't act on it (the
    // moment said it once; hover the notch for every agent).
    Item {
        id: lim
        readonly property alias hovered: limArea.containsMouse
        readonly property var b: Limits.backSoon
        visible: Limits.markShown
        // It arrives (fade + a small rise in scale), it doesn't pop.
        onVisibleChanged: if (visible && !Theme.reduceMotion) limIn.restart()
        ParallelAnimation {
            id: limIn
            NumberAnimation { target: lim; property: "opacity"; from: 0; to: 1; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            NumberAnimation { target: limRow; property: "scale"; from: 0.92; to: 1; duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: limRow.implicitWidth + 12
        implicitHeight: 22
        Rectangle {
            anchors.fill: parent; radius: height / 2
            color: Qt.rgba(1, 1, 1, limArea.pressed ? 0.14 : 0.09)
            opacity: limArea.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
        }
        Row {
            id: limRow
            anchors.centerIn: parent
            spacing: 5
            scale: limArea.pressed ? 0.96 : 1
            Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.OutCubic } }
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20
                StatRing {
                    anchors.fill: parent
                    size: 20; stroke: 2
                    // Drains as the reset nears (full at 15 min, empty at it).
                    value: lim.b ? Math.max(0, Math.min(1, (lim.b.at - Limits.now) / Limits.soonMs)) : 0
                    color: lim.b ? lim.b.tint : Theme.orange
                    text: ""; label: ""
                }
                Image {
                    anchors.centerIn: parent
                    width: 10; height: 10
                    source: lim.b ? lim.b.brand : ""
                    sourceSize: Qt.size(20, 20)
                    asynchronous: true
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 2      // digits sit optically low, as RestMark's
                text: lim.b ? Limits.compact(lim.b.at - Limits.now) : ""
                size: Theme.tSub; weight: Theme.wSemibold
                color: Theme.textSecondary
                font.features: ({ "tnum": 1 })
            }
        }
        MouseArea {
            id: limArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Island.open("usage", sys.bar ? sys.bar.screenName : "", "pointer", "island")
        }
        Timer {
            interval: Settings.hoverDelay
            running: limArea.containsMouse
            onTriggered: if (Island.panel === "" && sys.bar) Island.preview("usage", sys.bar.screenName)
        }
    }
}
