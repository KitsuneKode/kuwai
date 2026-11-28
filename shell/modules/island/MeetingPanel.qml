import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.components.ui as Ui
import qs.services

FocusScope {
    id: panel
    focus: true

    property string view: Meeting.startView !== "" ? Meeting.startView : (Meeting.active || Meeting.lastId !== "" ? "now" : "past")
    property real now: Date.now()
    readonly property bool deep: Meeting.detailId !== "" && view === "past"
    readonly property real inset: Theme.s4
    readonly property real ceiling: Math.min(Theme.panelMaxH, Theme.screenSize(Screen, "height", 1080) - 64)

    implicitWidth: Theme.panelS
    implicitHeight: Math.round(Math.min(ceiling, header.height + inset * 2 + Theme.s3 + body.implicitHeight))

    Timer { running: panel.visible && Meeting.active; interval: 1000; repeat: true; triggeredOnStart: true; onTriggered: panel.now = Date.now() }

    Component.onCompleted: {
        Meeting.startView = "";
        Meeting.loadList();
    }
    onDeepChanged: {
        if (deep) { Island.innerBack = () => Meeting.closeDetail(); Island.innerBackLabel = "Meetings"; }
        else if (Island.innerBackLabel === "Meetings") { Island.innerBack = null; Island.innerBackLabel = ""; }
    }
    Component.onDestruction: {
        if (Island.innerBackLabel === "Meetings") { Island.innerBack = null; Island.innerBackLabel = ""; }
        Meeting.closeDetail();
    }
    function pick(id) {
        if (id === view) return;
        view = id;
        if (id === "past") Meeting.loadList();
    }
    Keys.onPressed: e => {
        if (!(e.modifiers & Qt.AltModifier)) return;
        if (e.key === Qt.Key_1) pick("now");
        else if (e.key === Qt.Key_2) pick("past");
        else return;
        e.accepted = true;
    }

    readonly property var sections: [
        { id: "now", label: "Now", glyph: "\u{f147d}" },
        { id: "past", label: "Meetings", glyph: "\u{f02da}" }
    ]
    readonly property string heading: deep ? Meeting.nameOr(Meeting.detail || Meeting.meetings.find(m => m.id === Meeting.detailId))
        : view === "past" ? "Meetings"
        : Meeting.active ? (Meeting.title || "Meeting")
        : Meeting.lastId !== "" ? (Meeting.lastTitle || "Meeting")
        : "Meeting"

    Item {
        id: header
        x: panel.inset; y: panel.inset
        width: panel.width - 2 * panel.inset
        readonly property real line: Math.max(Theme.sp(26), title.implicitHeight)
        readonly property bool stack: title.implicitWidth + Theme.s3 + tabs.width > width
        height: stack ? line + Theme.s2 + tabs.height : Math.max(line, tabs.height)
        Label {
            id: title
            y: (header.line - implicitHeight) / 2
            width: Math.min(implicitWidth, header.width - (header.stack ? 0 : tabs.width + Theme.s3))
            elide: Text.ElideRight
            text: panel.heading
            size: Theme.tTitle3; weight: Theme.wSemibold
            Accessible.role: Accessible.Heading
        }
        SectionChips {
            id: tabs
            x: header.width - width
            y: header.stack ? header.line + Theme.s2 : (header.height - height) / 2
            model: panel.sections
            current: panel.view
            onPicked: id => panel.pick(id)
        }
    }

    ScrollFade { flickable: sheet }
    ScrollHint { flickable: sheet; inside: true }
    Flickable {
        id: sheet
        x: panel.inset
        y: header.y + header.height + Theme.s3
        width: panel.width - 2 * panel.inset
        height: panel.height - y - panel.inset
        contentWidth: width
        contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        property bool follow: true
        onMovementEnded: follow = atYEnd
        function toEnd() { contentY = follow && panel.view === "now" && Meeting.active ? Math.max(0, contentHeight - height) : Math.min(contentY, Math.max(0, contentHeight - height)); }
        onContentHeightChanged: toEnd()
        onHeightChanged: toEnd()

        Column {
            id: body
            width: sheet.width
            spacing: Theme.s3

            Loader {
                width: parent.width
                active: panel.view === "now"
                visible: active
                sourceComponent: nowView
            }
            Loader {
                width: parent.width
                active: panel.view === "past" && !panel.deep
                visible: active
                sourceComponent: listView
            }
            Loader {
                width: parent.width
                active: panel.deep
                visible: active
                sourceComponent: detailView
            }
        }
    }

    Component {
        id: nowView
        Column {
            width: parent ? parent.width : 0
            spacing: Theme.s3

            Loader { width: parent.width; active: !Meeting.active && Meeting.lastId === ""; visible: active; sourceComponent: idleState }

            Item {
                visible: Meeting.active || Meeting.lastId !== ""
                width: parent.width
                height: Math.max(statusLine.implicitHeight, controls.height)
                Row {
                    id: statusLine
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.s2
                    MeetingMark {
                        visible: Meeting.active
                        anchors.verticalCenter: parent.verticalCenter
                        moving: panel.visible
                        now: panel.now
                    }
                    Label {
                        visible: !Meeting.active
                        anchors.verticalCenter: parent.verticalCenter
                        text: Meeting.summarizing ? "Saved · writing the summary…" : "Saved"
                        size: Theme.tBody; weight: Theme.wSemibold
                        color: Theme.green
                    }
                }
                Row {
                    id: controls
                    visible: Meeting.active
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: Theme.s2
                    Ui.Button {
                        height: Theme.sp(28)
                        size: Theme.tFootnote
                        enabled: Meeting.phase === "live" || Meeting.phase === "paused"
                        glyph: Meeting.paused ? "\u{f040a}" : "\u{f03e4}"
                        text: Meeting.paused ? "Resume" : "Pause"
                        onClicked: Meeting.togglePause()
                    }
                    Ui.Button {
                        height: Theme.sp(28)
                        size: Theme.tFootnote
                        enabled: Meeting.phase !== "ending"
                        glyph: "\u{f04db}"
                        text: "Stop"
                        onClicked: Meeting.control("stop")
                    }
                }
            }

            Row {
                visible: Meeting.active && Meeting.live
                width: parent.width
                spacing: Theme.s3
                Repeater {
                    model: [{ name: "You", level: Meeting.micLevel }, { name: "Call", level: Meeting.callLevel }]
                    Row {
                        required property var modelData
                        visible: modelData.level >= 0 || modelData.name === "You"
                        spacing: Theme.s2
                        Label { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.name; size: Theme.tFootnote; color: Theme.textTertiary }
                        Ui.LevelBar {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.sp(72); height: Theme.s1
                            value: Math.max(0, parent.modelData.level)
                            glide: false
                        }
                    }
                }
            }

            Ui.Notice {
                visible: Meeting.notice
                width: parent.width
                glyph: "\u{f0026}"
                title: "Tell the others"
                detail: Meeting.noticeText || "Some places require everyone on a call to agree to a recording. Voxtype doesn't tell them for you, so let them know."
                detailLines: 8
                action: "OK"
                onActed: Meeting.ackNotice()
            }
            Ui.Notice {
                visible: Meeting.active && Meeting.trouble !== ""
                width: parent.width
                glyph: "\u{f036d}"
                title: "Nothing transcribed yet"
                detail: Meeting.trouble
                detailLines: 3
            }
            Label {
                visible: Meeting.active && Meeting.dictating
                width: parent.width
                wrapMode: Text.Wrap
                text: "You're dictating. The meeting records your microphone, so it hears this too."
                size: Theme.tFootnote
                color: Theme.orange
            }

            Flow {
                visible: Meeting.speakers.length > 0
                width: parent.width
                spacing: Theme.s2
                Repeater {
                    model: Meeting.speakers
                    Ui.Chip {
                        required property var modelData
                        text: modelData.name + " · " + modelData.lines
                        tone: modelData.you ? Theme.textPrimary : Theme.textSecondary
                    }
                }
            }

            Loader {
                width: parent.width
                active: !Meeting.active && (Meeting.summary !== null || Meeting.summarizing)
                visible: active
                sourceComponent: summaryCard
                onLoaded: { item.summary = Qt.binding(() => Meeting.summary); item.waiting = Qt.binding(() => Meeting.summarizing && !Meeting.summary); }
            }

            Transcript {
                width: parent.width
                segments: Meeting.segments
                hidden: Meeting.sharing
                listening: Meeting.live
            }

            Row {
                visible: !Meeting.active && Meeting.lastId !== ""
                spacing: Theme.s2
                Ui.Button {
                    height: Theme.sp(28)
                    size: Theme.tFootnote
                    text: "Open in Meetings"
                    onClicked: { panel.pick("past"); Meeting.show(Meeting.lastId); }
                }
                Ui.Button {
                    height: Theme.sp(28)
                    size: Theme.tFootnote
                    kind: "quiet"
                    text: "Record another"
                    onClicked: Meeting.start({})
                }
            }
        }
    }

    Component {
        id: idleState
        Column {
            width: parent ? parent.width : 0
            spacing: Theme.s3
            Ui.EmptyState {
                visible: Meeting.enabledState === "missing"
                width: parent.width
                glyph: "\u{f036d}"
                title: "Voxtype isn't installed"
                body: "Meetings are recorded and transcribed by voxtype, the voice-to-text app. Once it's installed, they show here."
            }
            Ui.EmptyState {
                visible: Meeting.enabledState === "off"
                width: parent.width
                glyph: "\u{f036c}"
                title: "Meetings are off in voxtype"
                body: "Turn them on to record calls with their transcript, speakers and a summary. Nothing records until you start it."
                actionLabel: "Turn on"
                onActionTriggered: Meeting.turnOn()
            }
            Ui.EmptyState {
                visible: Meeting.enabledState === "restart"
                width: parent.width
                glyph: "\u{f036c}"
                title: "Almost on"
                body: "Voxtype reads it when it starts. Restart it once you're not dictating."
                actionLabel: "Restart voxtype"
                onActionTriggered: Meeting.restartVoxtype()
            }
            Ui.EmptyState {
                visible: Meeting.enabledState === "on" || Meeting.enabledState === "unknown"
                width: parent.width
                glyph: "\u{f036c}"
                title: "No meeting is recording"
                body: "Start one here. A call, or a calendar event with a call link, offers it too; nothing records by itself."
                actionLabel: "Start recording"
                onActionTriggered: Meeting.start({})
            }
        }
    }

    Component {
        id: listView
        Column {
            width: parent ? parent.width : 0
            spacing: Theme.s1
            Label {
                visible: Meeting.listBusy && !Meeting.listLoaded
                width: parent.width
                wrapMode: Text.Wrap
                text: "Reading your meetings from voxtype…"
                size: Theme.tFootnote; color: Theme.textTertiary
            }
            Skeleton { visible: Meeting.listBusy && !Meeting.listLoaded; width: parent.width; height: Theme.sp(Theme.rowMin); radius: Theme.r2 }
            Skeleton { visible: Meeting.listBusy && !Meeting.listLoaded; width: parent.width; height: Theme.sp(Theme.rowMin); radius: Theme.r2 }
            Ui.Notice {
                visible: Meeting.listFailed && !Meeting.listBusy && Meeting.enabledState !== "missing"
                width: parent.width
                tone: Theme.red
                glyph: "\u{f0026}"
                title: "Couldn't read your meetings"
                detail: "Voxtype didn't answer. Try again in a moment."
                detailLines: 3
                action: "Try again"
                onActed: Meeting.loadList()
            }
            Ui.EmptyState {
                visible: Meeting.enabledState === "missing" && !Meeting.listLoaded
                width: parent.width
                glyph: "\u{f036d}"
                title: "Voxtype isn't installed"
                body: "Meetings are recorded and transcribed by voxtype, the voice-to-text app. Once it's installed, they show here."
            }
            Ui.EmptyState {
                visible: Meeting.listLoaded && Meeting.meetings.length === 0
                width: parent.width
                glyph: "\u{f02da}"
                title: "No meetings yet"
                body: "Meetings you record appear here, with their transcript, summary and action items."
            }
            Repeater {
                model: Meeting.meetings
                delegate: Item {
                    id: rowItem
                    required property var modelData
                    width: parent.width
                    height: row.height
                    Rectangle { anchors.fill: parent; radius: Theme.r2; color: Theme.wash(1); opacity: rowArea.containsMouse ? 1 : 0 }
                    ListRow {
                        id: row
                        width: parent.width
                        title: Meeting.nameOr(rowItem.modelData)
                        sub: Meeting.rowSub(rowItem.modelData, rowItem.modelData.startedAt ? Dates.day(new Date(rowItem.modelData.startedAt)) + (Theme.textScale < 1.5 ? " · " + Dates.time(new Date(rowItem.modelData.startedAt)) : "") : "")
                        stateText: Meeting.length(rowItem.modelData.secs)
                        lead: Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: rowItem.modelData.status === "interrupted" ? "\u{f0026}" : "\u{f0219}"
                            font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphM
                            color: rowItem.modelData.status === "interrupted" ? Theme.orange : Theme.textSecondary
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Meeting.show(rowItem.modelData.id)
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: row.title + ", " + row.sub
                    Accessible.onPressAction: Meeting.show(rowItem.modelData.id)
                }
            }
        }
    }

    Component {
        id: detailView
        Column {
            id: dv
            width: parent ? parent.width : 0
            spacing: Theme.s3
            readonly property var m: Meeting.detail
            readonly property var row: Meeting.meetings.find(x => x.id === Meeting.detailId) || null
            readonly property real at: m ? m.startedAt : row ? row.startedAt : 0
            readonly property real secs: m ? m.secs : row ? row.secs : 0

            Label {
                width: parent.width
                wrapMode: Text.Wrap
                text: [dv.at ? Dates.day(new Date(dv.at)) + " · " + Dates.time(new Date(dv.at)) : "", Meeting.length(dv.secs), dv.row && dv.row.speakers > 1 ? dv.row.speakers + " speakers" : ""].filter(x => x).join(" · ")
                size: Theme.tFootnote
                color: Theme.textTertiary
            }
            Flow {
                width: parent.width
                spacing: Theme.s2
                Ui.Button {
                    height: Theme.sp(28); size: Theme.tFootnote
                    glyph: "\u{f018f}"; text: Meeting.done === "copied" && Meeting.doneFor === Meeting.detailId ? "Copied" : "Copy"
                    onClicked: Meeting.copy(Meeting.detailId)
                }
                Ui.Button {
                    height: Theme.sp(28); size: Theme.tFootnote
                    glyph: "\u{f0193}"; text: Meeting.done === "saved" && Meeting.doneFor === Meeting.detailId ? "Saved in Documents" : "Save as Markdown"
                    onClicked: if (Meeting.done === "saved" && Meeting.doneFor === Meeting.detailId) Meeting.openSaved(); else Meeting.save(Meeting.detailId, dv.m ? dv.m.title : dv.row ? dv.row.title : "", dv.at)
                }
                Ui.Button {
                    height: Theme.sp(28); size: Theme.tFootnote
                    kind: Meeting.armed === Meeting.detailId ? "danger" : "quiet"
                    glyph: "\u{f0a7a}"
                    text: Meeting.armed === Meeting.detailId ? "Delete for good" : "Delete"
                    onClicked: Meeting.remove(Meeting.detailId)
                }
            }
            Skeleton { visible: Meeting.detailBusy; width: parent.width; height: Theme.sp(96); radius: Theme.r3 }
            Ui.Notice {
                visible: Meeting.detailFailed
                width: parent.width
                tone: Theme.red
                glyph: "\u{f0026}"
                title: "Couldn't open this meeting"
                detail: "Voxtype didn't answer. It may be busy finishing another meeting."
                action: "Try again"
                onActed: Meeting.show(Meeting.detailId)
            }
            Loader {
                width: parent.width
                active: !!dv.m && dv.m.summary !== null
                visible: active
                sourceComponent: summaryCard
                onLoaded: item.summary = Qt.binding(() => dv.m ? dv.m.summary : null)
            }
            Ui.Card {
                visible: !!dv.m && dv.m.notes !== ""
                Label { width: parent.width; text: "Notes"; size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textSecondary }
                Label { width: parent.width; wrapMode: Text.Wrap; text: dv.m ? dv.m.notes : ""; size: Theme.tSub }
            }
            Transcript {
                width: parent.width
                visible: !!dv.m
                segments: dv.m ? dv.m.segments : []
                hidden: Meeting.sharing
                listening: false
            }
        }
    }

    Component {
        id: summaryCard
        Ui.Card {
            id: sc
            property var summary: null
            property bool waiting: false
            Label { width: parent.width; text: "Summary"; size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textSecondary }
            Skeleton { visible: sc.waiting; width: parent.width; height: Theme.sp(40); radius: Theme.r1 }
            Label {
                visible: !!sc.summary && sc.summary.text !== ""
                width: parent.width
                wrapMode: Text.Wrap
                text: sc.summary ? sc.summary.text : ""
                size: Theme.tSub
                color: Meeting.sharing ? Theme.textTertiary : Theme.textPrimary
            }
            Label {
                visible: !!sc.summary && sc.summary.actions.length > 0
                width: parent.width
                text: "Action items"
                size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.textSecondary
            }
            Repeater {
                model: sc.summary ? sc.summary.actions : []
                Row {
                    required property var modelData
                    width: parent.width
                    spacing: Theme.s2
                    Text {
                        textFormat: Text.PlainText
                        text: parent.modelData.done ? "\u{f0135}" : "\u{f0131}"
                        font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphS
                        color: parent.modelData.done ? Theme.green : Theme.textSecondary
                    }
                    Label {
                        width: parent.width - Theme.glyphS - Theme.s2
                        wrapMode: Text.Wrap
                        text: parent.modelData.text + (parent.modelData.who ? " · " + parent.modelData.who : "")
                        size: Theme.tSub
                    }
                }
            }
        }
    }

    component Transcript: Column {
        id: tr
        property var segments: []
        property bool hidden: false
        property bool listening: false
        spacing: Theme.s3
        Label {
            visible: tr.hidden && tr.segments.length > 0
            width: parent.width
            wrapMode: Text.Wrap
            text: "The transcript is hidden while you share your screen."
            size: Theme.tFootnote; color: Theme.textTertiary
        }
        Repeater {
            model: tr.hidden ? [] : tr.segments
            Column {
                required property var modelData
                width: tr.width
                spacing: 2
                Row {
                    spacing: Theme.s2
                    Label {
                        text: parent.parent.modelData.who
                        size: Theme.tFootnote; weight: Theme.wSemibold
                        color: parent.parent.modelData.you ? Theme.textPrimary : Theme.textSecondary
                    }
                    Label {
                        text: Meeting.stamp(parent.parent.modelData.start)
                        size: Theme.tFootnote; color: Theme.textTertiary
                        tabular: true
                    }
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: parent.modelData.text
                    size: Theme.tSub
                    color: parent.modelData.note && parent.modelData.note.highlight ? Theme.yellow : Theme.textPrimary
                }
            }
        }
        Label {
            visible: tr.listening && !tr.hidden
            text: tr.segments.length ? "Listening… new lines arrive every half minute or so" : "Listening… the first lines arrive in about half a minute"
            width: parent.width
            wrapMode: Text.Wrap
            size: Theme.tFootnote; color: Theme.textTertiary
        }
    }
}
