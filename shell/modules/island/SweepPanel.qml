// Idle projects, grown out of the island (rest on the broom mark, or the
// launcher's "Idle Projects"). What sweep could free in one bar: each kind of
// leftover (node_modules, target, .next…) is a part of it. Rest on a part and
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
    // Looking (a rest on the mark counts) is what the mark was asking for.
    Component.onCompleted: { Sweep.check(); Sweep.markViewed(); }

    readonly property var tones: [Theme.green, Theme.cyan, Theme.orange, Theme.indigo]
    readonly property var segs: Model.segments(Sweep.kinds, Sweep.reclaimable, tones, 4)
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
    function caption() {
        const s = focused >= 0 ? segs[focused] : null;
        // The header counts the idle projects (what the mark said); the bar is
        // everything sweep found, so say so before a part is named.
        if (!s) return Model.long(Sweep.reclaimable) + " found in all · rest on a part";
        return (s.kind === "other" ? "Everything else" : s.kind) + " · " + Model.long(s.bytes)
            + (s.count ? " · " + s.count + (s.count === 1 ? " folder" : " folders") : "");
    }
    function toneOf(s) { return s.kind === "other" ? Theme.textTertiary : s.tone; }

    Column {
        id: col
        x: 20; y: 20
        width: panel.width - 40
        spacing: 14

        // ── Identity leads, the number trails ────────────────────────────
        Item {
            width: parent.width
            height: 26
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Sweep"
                size: Theme.tTitle2; weight: Theme.wBold; rounded: true
                color: Theme.green
            }
            Label {
                visible: Sweep.idleBytes > 0
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: Model.long(Sweep.idleBytes) + " idle · " + Sweep.idleProjects + (Sweep.idleProjects === 1 ? " project" : " projects")
                size: Theme.tCallout; weight: Theme.wSemibold
                color: Theme.green
                font.features: ({ "tnum": 1 })
            }
        }

        // ── Nothing to say ───────────────────────────────────────────────
        Label {
            visible: !Sweep.alive || Sweep.pending || panel.segs.length === 0
            width: parent.width
            topPadding: 4; bottomPadding: 4
            wrapMode: Text.WordWrap
            text: !Sweep.alive ? "sweep isn't installed, or hasn't counted anything yet."
                : Sweep.pending ? "Counting…  the first scan takes a few seconds."
                : "Nothing to free here."
            size: Theme.tBody; color: Theme.textTertiary
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
            text: "Idle " + Sweep.idleDays + "+ days"
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
                text: (Sweep.protectedCount > 0 ? Sweep.protectedCount + " protected · " : "") + "counted " + Model.agoText(Sweep.checkedAt, Date.now())
                size: Theme.tCaption
                color: Theme.textTertiary
                elide: Text.ElideLeft
            }
        }
        Label {
            visible: Sweep.alive
            width: parent.width
            text: "Nothing is deleted from here. sweep asks before it removes anything."
            size: Theme.tCaption
            color: Theme.textTertiary
            wrapMode: Text.WordWrap
        }
    }
}
