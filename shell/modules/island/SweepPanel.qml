// Idle projects, grown out of the island (rest on the broom mark, or the
// launcher's "Idle Projects"). What the idle projects hold in one bar (the
// header's number; a sweep that can't split them shows all it found, and
// says so): each kind of leftover (node_modules, target, .next…) is a part. Rest on a part and
// the others step back while the caption names it (as in sweep's own project
// view); below, the old projects holding the most. Look, then decide: nothing
// is deleted from here. Enter (or the button) opens sweep's review.
//   Enter / click a row or the button: sweep, in a terminal. Esc closes.
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services
import "../../services/sweepModel.js" as Model

FocusScope {
    id: panel
    focus: true
    implicitWidth: 420
    implicitHeight: col.implicitHeight + 40

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { Sweep.openUi(); Island.close(); e.accepted = true; }
    }
    // Looking is what the mark was asking for. Opened on purpose (a click, a
    // key, the launcher): looked at once. Grown by a rest of the pointer
    // (a preview, ~220 ms): only after it has stayed open a moment, so the
    // pointer passing over the mark doesn't count.
    readonly property int dwellMs: 1500
    Component.onCompleted: { Sweep.check(true); if (!Island.previewing) Sweep.markViewed(); }
    Timer { interval: panel.dwellMs; running: Island.previewing && panel.visible; onTriggered: Sweep.markViewed() }

    readonly property var tones: [Theme.green, Theme.cyan, Theme.orange, Theme.indigo]
    // The bar splits the idle projects' space, so it adds up to the header's
    // number. A sweep without that split: all it found, labelled as such.
    readonly property bool idleSplit: Sweep.idleKinds.length > 0 && Sweep.idleBytes > 0
    readonly property var segs: idleSplit ? Model.segments(Sweep.idleKinds, Sweep.idleBytes, tones, 4)
        : Model.segments(Sweep.kinds, Sweep.reclaimable, tones, 4)
    // The part under the pointer; -1 when none. The others recede to
    // `dimTo`, the same share sweep's own bar leaves them.
    property int focused: -1
    readonly property real dimTo: 0.38
    property Item hoverRow: null
    // The bar draws itself in once, left to right, as it opens. Reduced
    // motion: already there.
    property real reveal: 1
    NumberAnimation on reveal {
        from: 0; to: 1
        duration: Theme.reduceMotion ? 0 : Theme.ringDrawMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut
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

        // ── Title: what it is, then the number (as Usage, Agents) ────────
        Item {
            width: parent.width
            height: 26
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Sweep"
                size: Theme.tTitle3; weight: Theme.wSemibold   // the panels' one title style
            }
            // Neutral: a size isn't a state. Orange only when the last count failed.
            Label {
                visible: Sweep.idleBytes > 0
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: Model.headline(Sweep.idleBytes, Sweep.idleProjects, Sweep.idleDays)
                size: Theme.tFootnote; weight: Theme.wSemibold
                color: Sweep.error && !Sweep.refreshing ? Theme.orange : Theme.textTertiary
                font.features: ({ "tnum": 1 })
            }
        }

        // ── Nothing to say ───────────────────────────────────────────────
        Label {
            visible: panel.empty !== ""
            width: parent.width
            topPadding: 4; bottomPadding: 4
            wrapMode: Text.WordWrap
            text: panel.empty
            size: Theme.tBody; color: Sweep.error && !Sweep.counted ? Theme.orange : Theme.textTertiary
        }

        // ── The bar ──────────────────────────────────────────────────────
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
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: panel.segs
                        Rectangle {
                            id: seg
                            required property int index
                            required property var modelData
                            readonly property real room: bar.width - (panel.segs.length - 1) * 2
                            width: Math.max(4, Math.round(modelData.share * room))
                            height: 10
                            radius: 3
                            color: panel.toneOf(modelData)
                            opacity: panel.focused < 0 || panel.focused === index ? 1 : panel.dimTo
                            Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
                            // The hover zone is taller than the part: ten pixels is
                            // a small target.
                            MouseArea {
                                anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
                                hoverEnabled: true
                                onContainsMouseChanged: {
                                    if (containsMouse) panel.focused = seg.index;
                                    else if (panel.focused === seg.index) panel.focused = -1;
                                }
                            }
                        }
                    }
                }
            }
        }
        Label {
            id: cap
            visible: panel.segs.length > 0
            width: parent.width
            text: panel.caption()
            size: Theme.tSub; weight: Theme.wMedium
            color: panel.focused >= 0 ? Theme.textPrimary : Theme.textSecondary
            elide: Text.ElideRight
            font.features: ({ "tnum": 1 })
            // Naming a different part: the caption answers with a short fade.
            onTextChanged: if (!Theme.reduceMotion) capIn.restart()
            NumberAnimation { id: capIn; target: cap; property: "opacity"; from: 0.35; to: 1; duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }

        // ── The old projects holding the most ────────────────────────────
        Label {
            visible: Sweep.projects.length > 0
            text: "Holding the most"
            size: Theme.tCaption; weight: Theme.wSemibold
            color: Theme.textTertiary
        }
        Item {
            id: list
            visible: Sweep.projects.length > 0
            width: parent.width
            readonly property int rowH: 34
            height: Sweep.projects.length * rowH
            FluidHighlight { radius: Theme.r2; target: panel.hoverRow }
            Repeater {
                model: Sweep.projects
                Item {
                    id: row
                    required property var modelData
                    required property int index
                    y: index * list.rowH
                    width: list.width
                    height: list.rowH
                    Label {
                        anchors { left: parent.left; leftMargin: 10; right: meta.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: row.modelData.name
                        size: Theme.tBody; weight: Theme.wMedium
                        elide: Text.ElideRight
                    }
                    Label {
                        id: meta
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: Model.idleText(row.modelData.idleDays) + " · " + Model.long(row.modelData.bytes)
                        size: Theme.tSub
                        color: Theme.textTertiary
                        font.features: ({ "tnum": 1 })
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: { if (containsMouse) panel.hoverRow = row; else if (panel.hoverRow === row) panel.hoverRow = null; }
                        onClicked: { Sweep.openUi(); Island.close(); }
                    }
                }
            }
        }

        // ── Look, then decide ────────────────────────────────────────────
        Item {
            visible: Sweep.alive
            width: parent.width
            height: 30
            PillButton {
                id: review
                anchors.verticalCenter: parent.verticalCenter
                text: "Review in sweep"
                onClicked: { Sweep.openUi(); Island.close(); }
            }
            Label {
                anchors { left: review.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
                horizontalAlignment: Text.AlignRight
                // No time before the first count; "counting again…" while a
                // refresh runs behind what's shown, the failure if it didn't.
                text: Model.footText({ protectedCount: Sweep.protectedCount, checkedAt: Sweep.checkedAt, pending: Sweep.pending,
                    refreshing: Sweep.refreshing, error: Sweep.error, counted: Sweep.counted }, Date.now())
                size: Theme.tCaption
                color: Sweep.error && !Sweep.refreshing ? Theme.orange : Theme.textTertiary
                elide: Text.ElideLeft
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
