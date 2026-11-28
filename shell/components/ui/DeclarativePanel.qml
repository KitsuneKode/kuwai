import QtQuick
import qs.config
import qs.components
import "../../services/panelSchema.mjs" as Schema

FocusScope {
    id: dp
    property var model: null
    property real maxHeight: Theme.panelMaxH
    property var keyHints: []
    property bool keyboard: false
    property real pad: Theme.s4 + Theme.s1
    signal intent(string id, string rowId, string url)

    readonly property var result: Schema.validate(model)
    readonly property var p: result.ok ? result.panel : Schema.brokenPanel(model && typeof model.id === "string" ? model.id : "panel", "")
    readonly property bool loading: p.state === "loading"
    readonly property var vis: p.visualization
    readonly property var rows: p.rows

    property int sel: -1
    property int focused: -1
    property bool barKeys: false
    property Item hoverRow: null
    onRowsChanged: sel = Math.min(sel, rows.length - 1)
    onVisChanged: focused = vis ? Math.min(focused, vis.buckets.length - 1) : -1

    implicitWidth: Theme.panelS
    implicitHeight: Math.min(col.implicitHeight + pad * 2, maxHeight)
    focus: true

    function toneColour(t) {
        switch (t) {
        case "good": return Theme.green;
        case "warn": return Theme.orange;
        case "bad": return Theme.red;
        case "info": return Theme.cyan;
        default: return Theme.textSecondary;
        }
    }
    function toneIcon(t) {
        switch (t) {
        case "good": return "check-circle";
        case "warn": return "warning";
        case "bad": return "warning-circle";
        default: return "info";
        }
    }
    function fire(id, rowId, url) { if (id) dp.intent(id, rowId || "", url || ""); }
    function activate() {
        const r = sel >= 0 ? rows[sel] : null;
        if (r && r.actionId) fire(r.actionId, r.id, "");
        else if (p.primaryAction) fire(p.primaryAction.id, "", p.primaryAction.url);
        else if (p.notice && p.notice.actionId) fire(p.notice.actionId, "", p.notice.url);
        else if (p.empty && p.empty.actionId) fire(p.empty.actionId, "", p.empty.url);
    }
    function reveal(f, top, h) {
        if (!f.interactive) return;
        if (top < f.contentY) f.contentY = top;
        else if (top + h > f.contentY + f.height) f.contentY = top + h - f.height;
    }
    function showSel() {
        const it = sel >= 0 ? rowsRep.itemAt(sel) : null;
        if (!it) return;
        reveal(listFlick, it.y, it.height);
        reveal(flick, it.mapToItem(col, 0, 0).y + pad, it.height);
    }
    readonly property real listMax: {
        let h = 0, k = 0;
        for (const c of col.children) if (c.visible) { k++; if (c !== listBox) h += c.height; }
        return Math.max(Theme.sp(34) * 2, maxHeight - pad * 2 - h - Math.max(0, k - 1) * col.spacing);
    }
    onSelChanged: Qt.callLater(showSel)
    Keys.onPressed: e => {
        const n = vis ? vis.buckets.length : 0;
        if (e.key === Qt.Key_Down && rows.length) { keyboard = true; sel = Math.min(rows.length - 1, sel + 1); }
        else if (e.key === Qt.Key_Up && rows.length) { keyboard = true; sel = Math.max(-1, sel - 1); }
        else if (e.key === Qt.Key_Right && n) { barKeys = true; focused = Math.min(n - 1, focused + 1); }
        else if (e.key === Qt.Key_Left && n) { barKeys = true; focused = Math.max(-1, focused - 1); }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) activate();
        else return;
        e.accepted = true;
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight + dp.pad * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height + 1
        Column {
            id: col
            x: dp.pad; y: dp.pad
            width: dp.width - dp.pad * 2
            spacing: Theme.s3 + 2

            Column {
                visible: dp.p.title !== "" || dp.p.subtitle !== ""
                width: parent.width
                spacing: 2
                Label {
                    visible: dp.p.title !== ""
                    width: parent.width
                    elide: Text.ElideRight
                    text: dp.p.title
                    size: Theme.tTitle3; weight: Theme.wSemibold
                    Accessible.role: Accessible.Heading
                }
                Label {
                    visible: dp.p.subtitle !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: dp.p.subtitle
                    size: Theme.tSub
                    color: Theme.textSecondary
                }
            }

            Column {
                visible: dp.loading
                width: parent.width
                spacing: Theme.s3
                Accessible.role: Accessible.StaticText
                Accessible.name: dp.p.subtitle || "Loading"
                Skeleton { width: parent.width * 0.42; height: Theme.sp(26) }
                Skeleton { width: parent.width; height: Theme.sp(34) }
                Repeater {
                    model: 3
                    Skeleton { required property int index; width: parent.width * (0.9 - index * 0.14); height: Theme.sp(14) }
                }
            }

            Column {
                id: hero
                visible: !!dp.p.hero && !dp.loading
                width: parent.width
                spacing: 2
                readonly property bool stack: heroValue.implicitWidth + Theme.s3 + heroLabel.implicitWidth > width
                Item {
                    width: parent.width
                    height: hero.stack ? heroValue.implicitHeight + heroLabel.implicitHeight : Math.max(heroValue.implicitHeight, heroLabel.implicitHeight)
                    Label {
                        id: heroValue
                        text: dp.p.hero ? dp.p.hero.value : ""
                        size: Theme.tTitle1; weight: Theme.wBold; rounded: true
                        color: dp.p.hero && dp.p.hero.tone !== "neutral" && dp.p.hero.tone !== "muted" ? dp.toneColour(dp.p.hero.tone) : Theme.textPrimary
                        tabular: true
                    }
                    Label {
                        id: heroLabel
                        x: hero.stack ? 0 : heroValue.implicitWidth + Theme.s2
                        y: hero.stack ? heroValue.implicitHeight : heroValue.y + heroValue.baselineOffset - baselineOffset
                        width: hero.stack ? parent.width : parent.width - x
                        elide: Text.ElideRight
                        text: dp.p.hero ? dp.p.hero.label : ""
                        size: Theme.tSub; weight: Theme.wMedium
                        color: Theme.textSecondary
                    }
                }
                Label {
                    visible: text !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: dp.p.hero ? dp.p.hero.detail : ""
                    size: Theme.tFootnote
                    color: Theme.textTertiary
                    tabular: true
                }
            }

            Notice {
                visible: !!dp.p.notice && !dp.loading
                icon: dp.p.notice ? dp.toneIcon(dp.p.notice.tone) : ""
                tone: dp.p.notice ? dp.toneColour(dp.p.notice.tone) : Theme.orange
                title: dp.p.notice ? dp.p.notice.title : ""
                detail: dp.p.notice ? dp.p.notice.detail : ""
                action: dp.p.notice ? dp.p.notice.actionLabel : ""
                detailLines: 4
                onActed: dp.fire(dp.p.notice.actionId, "", dp.p.notice.url)
            }

            EmptyState {
                visible: !!dp.p.empty && !dp.loading
                topPadding: Theme.s3
                bottomPadding: Theme.s2
                icon: dp.p.empty ? dp.p.empty.icon : ""
                title: dp.p.empty ? dp.p.empty.title : ""
                body: dp.p.empty ? dp.p.empty.detail : ""
                actionLabel: dp.p.empty ? dp.p.empty.actionLabel : ""
                onActionTriggered: dp.fire(dp.p.empty.actionId, "", dp.p.empty.url)
            }

            Column {
                visible: !!dp.vis && !dp.loading
                width: parent.width
                spacing: Theme.s2
                DotBar {
                    visible: !!dp.vis && dp.vis.type === "dotBar"
                    width: parent.width
                    buckets: dp.vis ? dp.vis.buckets : []
                    total: dp.vis ? dp.vis.total : 0
                    label: dp.vis ? dp.vis.label : ""
                    focused: dp.focused
                    keys: dp.barKeys
                    legend: false
                    onPointed: i => { dp.barKeys = false; dp.focused = i; }
                }
                Rectangle {
                    id: meter
                    visible: !!dp.vis && dp.vis.type === "meter"
                    width: parent.width
                    height: Theme.s2
                    radius: height / 2
                    color: Theme.wash(2)
                    readonly property real share: dp.vis && dp.vis.total > 0 ? Math.min(1, dp.vis.buckets.reduce((t, b) => t + b.value, 0) / dp.vis.total) : 0
                    Accessible.role: Accessible.ProgressBar
                    Accessible.name: dp.vis ? dp.vis.label + " " + Math.round(share * 100) + "%" : ""
                    Rectangle {
                        width: Math.max(height, parent.width * meter.share)
                        visible: meter.share > 0
                        height: parent.height
                        radius: parent.radius
                        color: dp.vis && dp.vis.buckets.length ? dp.toneColour(dp.vis.buckets[0].tone) : Theme.cyan
                        Behavior on width { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.quickMs } }
                    }
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    readonly property var b: dp.vis && dp.focused >= 0 ? dp.vis.buckets[dp.focused] : null
                    text: b ? b.label + (b.detail ? " · " + b.detail : "") : dp.vis ? dp.vis.label + (dp.vis.type === "dotBar" && dp.vis.buckets.length > 1 ? " · rest on a part" : "") : ""
                    size: Theme.tSub; weight: Theme.wMedium
                    color: b ? Theme.textPrimary : Theme.textSecondary
                    tabular: true
                }
            }

            Label {
                visible: dp.rows.length > 0 && dp.p.rowsLabel !== "" && !dp.loading
                text: dp.p.rowsLabel
                size: Theme.tCaption; weight: Theme.wSemibold
                color: Theme.textTertiary
            }
            Item {
                id: listBox
                visible: dp.rows.length > 0 && !dp.loading
                width: parent.width
                height: Math.min(list.implicitHeight, dp.listMax)
                Flickable {
                    id: listFlick
                    anchors.fill: parent
                    contentHeight: list.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height + 1
                    Column {
                        id: list
                        width: listFlick.width
                        FluidHighlight {
                            radius: Theme.r2
                            target: dp.keyboard ? (dp.sel >= 0 ? rowsRep.itemAt(dp.sel) : null) : dp.hoverRow
                            ring: dp.keyboard
                        }
                        Repeater {
                            id: rowsRep
                            model: dp.rows
                            Item {
                                id: row
                                required property var modelData
                                required property int index
                                width: list.width
                                readonly property bool acts: modelData.actionId !== ""
                                readonly property string side: [modelData.badge, modelData.meta].filter(x => x).join(" · ")
                                readonly property bool stack: rowTitle.implicitWidth + rowMeta.implicitWidth + Theme.s5 + Theme.s2 > width
                                height: Math.max(Theme.sp(34), (stack ? rowTitle.implicitHeight + rowMeta.implicitHeight + 2 : Math.max(rowTitle.implicitHeight, rowMeta.implicitHeight))
                                    + (rowDetail.visible ? rowDetail.implicitHeight + 2 : 0) + Theme.s2 + (stack ? Theme.s1 : 0))
                                Accessible.role: acts ? Accessible.Button : Accessible.StaticText
                                Accessible.name: [modelData.title, modelData.detail, side].filter(x => x).join(", ")
                                Accessible.onPressAction: if (row.acts) dp.fire(row.modelData.actionId, row.modelData.id, "")
                                Label {
                                    id: rowTitle
                                    x: Theme.s2 + 2
                                    y: Theme.s1 + (row.stack ? 0 : Math.max(0, (rowMeta.implicitHeight - implicitHeight) / 2))
                                    width: row.stack ? row.width - Theme.s4 - Theme.s1 : row.width - Theme.s5 - Theme.s2 - rowMeta.implicitWidth
                                    elide: Text.ElideMiddle
                                    text: row.modelData.title
                                    size: Theme.tBody; weight: Theme.wMedium
                                }
                                Label {
                                    id: rowDetail
                                    visible: text !== ""
                                    x: rowTitle.x
                                    y: rowTitle.y + rowTitle.implicitHeight + 2
                                    width: rowTitle.width
                                    elide: Text.ElideRight
                                    text: row.modelData.detail
                                    size: Theme.tFootnote
                                    color: Theme.textTertiary
                                }
                                Label {
                                    id: rowMeta
                                    x: row.stack ? rowTitle.x : row.width - Theme.s2 - 2 - implicitWidth
                                    y: row.stack ? (rowDetail.visible ? rowDetail.y + rowDetail.implicitHeight : rowTitle.y + rowTitle.implicitHeight) + 2 : rowTitle.y
                                    text: row.side
                                    size: Theme.tSub
                                    color: Theme.textTertiary
                                    tabular: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: row.acts ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onContainsMouseChanged: {
                                        if (containsMouse) { dp.keyboard = false; dp.sel = row.index; dp.hoverRow = row; }
                                        else if (dp.hoverRow === row) dp.hoverRow = null;
                                    }
                                    onClicked: if (row.acts) dp.fire(row.modelData.actionId, row.modelData.id, "")
                                }
                            }
                        }
                    }
                }
                ScrollFade { flickable: listFlick }
                ScrollHint { flickable: listFlick; inside: true }
            }

            KeyHints {
                visible: dp.keyHints.length > 0 && !dp.loading
                hints: dp.keyHints
            }

            Button {
                visible: !!dp.p.primaryAction && !dp.loading
                height: Theme.sp(30); size: Theme.tSub
                kind: "primary"
                text: dp.p.primaryAction ? dp.p.primaryAction.label : ""
                onClicked: dp.fire(dp.p.primaryAction.id, "", dp.p.primaryAction.url)
            }

            Label {
                visible: dp.p.footnote !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: dp.p.footnote
                size: Theme.tCaption
                color: Theme.textTertiary
            }
        }
    }
    ScrollFade { flickable: flick }
    ScrollHint { flickable: flick; inside: true }
}
