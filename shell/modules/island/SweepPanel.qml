import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.components.ui as Ui
import "../../services/sweepModel.js" as Model

FocusScope {
    id: panel
    focus: true
    implicitWidth: Theme.panelS
    implicitHeight: col.implicitHeight + 40
    readonly property real ceiling: Math.min(Theme.panelMaxH, Theme.screenSize(Screen, "height", 1080) - 24) - 40 - 34
    onSelChanged: Qt.callLater(showSel)
    function showSel() {
        const it = sel >= 0 ? rowsRep.itemAt(sel) : null;
        if (!it || !listFlick.interactive) return;
        if (it.y < listFlick.contentY) listFlick.contentY = it.y;
        else if (it.y + it.height > listFlick.contentY + listFlick.height) listFlick.contentY = it.y + it.height - listFlick.height;
    }
    readonly property real listMax: {
        let h = 0, n = 0;
        for (const c of col.children) if (c.visible) { n++; if (c !== listBox) h += c.height; }
        return Math.max(Theme.sp(34), ceiling - 40 - h - Math.max(0, n - 1) * col.spacing);
    }

    property int sel: -1
    property bool keyboard: false
    property bool barKeys: false
    onSegsChanged: focused = Math.min(focused, segs.length - 1)
    Connections {
        target: Sweep
        function onProjectsChanged() { panel.sel = Math.min(panel.sel, Sweep.projects.length - 1); }
    }
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Down) { keyboard = true; sel = Math.min(Sweep.projects.length - 1, sel + 1); }
        else if (e.key === Qt.Key_Up) { keyboard = true; sel = Math.max(-1, sel - 1); }
        else if (e.key === Qt.Key_Right) { barKeys = true; focused = Math.min(segs.length - 1, focused + 1); }
        else if (e.key === Qt.Key_Left) { barKeys = true; focused = Math.max(-1, focused - 1); }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            const p = sel >= 0 ? Sweep.projects[sel] : null;
            Sweep.openUi(p ? p.path : "");
            Island.close();
        }
        else return;
        Sweep.markViewed();
        e.accepted = true;
    }
    readonly property int dwellMs: 1500
    readonly property int freshS: 1800
    Component.onCompleted: { Sweep.check(true, panel.freshS); if (!Island.previewing) Sweep.markViewed(); }
    Timer { interval: panel.dwellMs; running: Island.previewing && panel.visible; onTriggered: Sweep.markViewed() }

    readonly property var tones: [Theme.green, Theme.cyan, Theme.orange, Theme.indigo]
    readonly property bool idleSplit: Sweep.idleKinds.length > 0 && Sweep.idleBytes > 0
    readonly property var segs: idleSplit ? Model.segments(Sweep.idleKinds, Sweep.idleBytes, tones, 4)
        : Model.segments(Sweep.kinds, Sweep.reclaimable, tones, 4)
    property int focused: -1
    readonly property real dimTo: 0.38
    property Item hoverRow: null
    property real reveal: 1
    NumberAnimation on reveal {
        from: 0; to: 1
        duration: Theme.reduceMotion || Island.via === "key" ? 0 : Theme.enterMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut
    }
    readonly property int segGap: 2
    readonly property var segWidths: Model.widths(segs, bar.width, segGap)
    property int lastFocused: -1
    onFocusedChanged: {
        if (focused >= 0 && lastFocused < 0 && !barKeys && !Theme.reduceMotion) capIn.restart();
        else if (barKeys) { capIn.stop(); cap.opacity = 1; }
        lastFocused = focused;
    }
    function caption() { return Model.caption(focused >= 0 ? segs[focused] : null, idleSplit, Sweep.reclaimable); }
    readonly property string empty: Model.emptyText({ loaded: Sweep.loaded, alive: Sweep.alive, pending: Sweep.pending, error: Sweep.error,
        counted: Sweep.counted, root: Sweep.scanRoot, home: Quickshell.env("HOME"), hasBar: segs.length > 0 })
    function toneOf(s) { return s.kind === "other" ? Theme.textTertiary : s.tone; }

    Column {
        id: col
        x: 20; y: 20
        width: panel.width - 40
        spacing: 14

        Item {
            id: head
            width: parent.width
            readonly property bool stack: headline.visible && headTitle.implicitWidth + Theme.s3 + headline.implicitWidth > width
            height: stack ? headTitle.implicitHeight + 2 + headline.implicitHeight : Math.max(Theme.sp(26), headTitle.implicitHeight)
            Label {
                id: headTitle
                y: head.stack ? 0 : (head.height - implicitHeight) / 2
                text: "Idle projects"
                size: Theme.tTitle3; weight: Theme.wSemibold
            }
            Label {
                id: headline
                visible: Sweep.idleBytes > 0
                x: head.stack ? 0 : head.width - implicitWidth
                y: head.stack ? headTitle.implicitHeight + 2 : (head.height - implicitHeight) / 2
                width: head.stack ? head.width : implicitWidth
                wrapMode: head.stack ? Text.Wrap : Text.NoWrap
                text: Model.headline(Sweep.idleBytes, Sweep.idleProjects, Sweep.idleDays)
                size: Theme.tFootnote; weight: Theme.wSemibold
                color: Sweep.error && !Sweep.refreshing ? Theme.orange : Theme.textTertiary
                font.features: ({ "tnum": 1 })
            }
        }

        Label {
            visible: panel.empty !== ""
            width: parent.width
            topPadding: 4; bottomPadding: 4
            wrapMode: Text.WordWrap
            text: panel.empty
            size: Theme.tBody; color: Sweep.error && !Sweep.counted ? Theme.orange : Theme.textTertiary
        }

        Item {
            id: bar
            visible: panel.segs.length > 0
            width: parent.width
            height: 22
            Item {
                id: wipe
                width: bar.width * panel.reveal
                height: bar.height
                clip: true
                Row {
                    spacing: panel.segGap
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: panel.segs
                        Rectangle {
                            id: seg
                            required property int index
                            required property var modelData
                            width: panel.segWidths[index] || 4
                            height: 10
                            radius: 3
                            color: panel.toneOf(modelData)
                            opacity: panel.focused < 0 || panel.focused === index ? 1 : panel.dimTo
                            Behavior on opacity {
                                enabled: !panel.barKeys && !Theme.reduceMotion
                                NumberAnimation { duration: Theme.hoverMs }
                            }
                        }
                    }
                }
            }
            MouseArea {
                anchors { fill: parent; topMargin: -4; bottomMargin: -4 }
                hoverEnabled: true
                function name(x) { panel.barKeys = false; panel.focused = Model.partAt(x, panel.segWidths, panel.segGap); }
                onEntered: name(mouseX)
                onPositionChanged: mouse => name(mouse.x)
                onExited: if (!panel.barKeys) panel.focused = -1
            }
        }
        Label {
            id: cap
            visible: panel.segs.length > 0
            width: parent.width
            text: panel.caption()
            size: Theme.tSub; weight: Theme.wMedium
            color: panel.focused >= 0 ? Theme.textPrimary : Theme.textSecondary
            wrapMode: Text.Wrap
            font.features: ({ "tnum": 1 })
            NumberAnimation { id: capIn; target: cap; property: "opacity"; from: 0.35; to: 1; duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }

        Label {
            visible: Sweep.projects.length > 0
            text: "Holding the most"
            size: Theme.tCaption; weight: Theme.wSemibold
            color: Theme.textTertiary
        }
        Item {
          id: listBox
          visible: Sweep.projects.length > 0
          width: parent.width
          height: Math.min(list.implicitHeight, panel.listMax)
        Flickable {
            id: listFlick
            anchors.fill: parent
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
        Column {
            id: list
            width: listFlick.width
            FluidHighlight {
                radius: Theme.r2
                target: panel.keyboard ? (panel.sel >= 0 ? rowsRep.itemAt(panel.sel) : null) : panel.hoverRow
                ring: panel.keyboard
            }
            Repeater {
                id: rowsRep
                model: Sweep.projects
                Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    readonly property var at: Model.where(modelData.path, modelData.name)
                    Accessible.role: Accessible.Button
                    Accessible.name: (row.at.repo ? row.at.repo + " › " : "") + row.at.name + ", idle " + Model.idleText(row.modelData.idleDays) + ", " + Model.long(row.modelData.bytes)
                    Accessible.description: "Opens sweep's review of this project"
                    Accessible.onPressAction: { Sweep.openUi(row.modelData.path); Island.close(); }
                    readonly property bool stack: repoName.implicitWidth + nameLabel.implicitWidth + meta.implicitWidth + 32 > width
                    height: stack ? nameRow.height + meta.implicitHeight + Theme.s3 : Math.max(Theme.sp(34), nameRow.height + Theme.s2)
                    Row {
                        id: nameRow
                        x: 10
                        y: row.stack ? Theme.s1 : (row.height - height) / 2
                        width: row.stack ? row.width - 20 : row.width - 32 - meta.implicitWidth
                        spacing: 0
                        Label {
                            id: repoName
                            visible: row.at.repo !== ""
                            text: row.at.repo + " › "
                            size: Theme.tBody
                            color: Theme.textTertiary
                        }
                        Label {
                            id: nameLabel
                            width: parent.width - (repoName.visible ? repoName.width : 0)
                            text: row.at.name
                            size: Theme.tBody; weight: Theme.wMedium
                            elide: Text.ElideRight
                        }
                    }
                    Label {
                        id: meta
                        x: row.stack ? 10 : row.width - 10 - implicitWidth
                        y: row.stack ? nameRow.y + nameRow.height + 2 : (row.height - implicitHeight) / 2
                        text: Model.idleText(row.modelData.idleDays) + " · " + Model.long(row.modelData.bytes)
                        size: Theme.tSub
                        color: Theme.textTertiary
                        font.features: ({ "tnum": 1 })
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: {
                            if (containsMouse) { panel.keyboard = false; panel.sel = row.index; panel.hoverRow = row; }
                            else if (panel.hoverRow === row) panel.hoverRow = null;
                        }
                        onClicked: { Sweep.openUi(row.modelData.path); Island.close(); }
                    }
                }
            }
        }
        }
        ScrollFade { flickable: listFlick }
        }

        KeyHints {
            visible: Island.via === "key" && Sweep.alive
            hints: [["↑↓", "Project"], ["←→", "Part"], ["↩", "Review in sweep"], ["esc", "Back"]]
        }

        Column {
            visible: Sweep.alive
            width: parent.width
            spacing: Theme.s2
            Ui.Button {
                id: review
                height: Theme.sp(30); size: Theme.tSub
                text: "Review in sweep"
                onClicked: { Sweep.openUi(); Island.close(); }
            }
            Label {
                width: parent.width
                wrapMode: Text.Wrap
                text: Model.footText({ protectedCount: Sweep.protectedCount, checkedAt: Sweep.checkedAt, pending: Sweep.pending,
                    refreshing: Sweep.refreshing, error: Sweep.error, counted: Sweep.counted }, Date.now())
                size: Theme.tCaption
                color: Sweep.error && !Sweep.refreshing ? Theme.orange : Theme.textTertiary
            }
        }
        Label {
            visible: Sweep.alive
            width: parent.width
            text: "Nothing is deleted from here. sweep asks before it removes anything."
                + (Settings.sweepMark ? "" : " The idle projects mark is off in Settings → Island.")
            size: Theme.tCaption
            color: Theme.textTertiary
            wrapMode: Text.WordWrap
        }
    }
}
