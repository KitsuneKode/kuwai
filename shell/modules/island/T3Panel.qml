// T3 Code at a glance, grown out of the island (hover the T3 mark on the
// notch, or click it). Like the "T3 · 24 active" live activity: the wordmark
// and how many are active, then each thread: what state it's in, its title,
// which agent runs it. Threads waiting for you come first, in orange.
//   Enter / click a row or the button: bring T3 Code forward. Esc closes.
//   Right-click a row: open it, show its last reply, copy its title, dismiss
//   it (finished ones), or dismiss every finished one.
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.components.ui
import qs.services
import "../../services/t3.mjs" as T3

FocusScope {
    id: t3
    focus: true
    implicitWidth: Theme.panelS
    implicitHeight: col.implicitHeight + 40

    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { T3Code.openBest(); Island.close(); e.accepted = true; }
    }

    property Item hoverRow: null
    // The thread whose last reply is showing: the row the pointer has rested
    // on for a moment (Theme.tipMs). One at a time; leaving the row closes it.
    property string previewOf: ""
    property real now: Date.now()
    Timer { interval: 30000; running: t3.visible; repeat: true; triggeredOnStart: true; onTriggered: t3.now = Date.now() }
    readonly property var live: T3Code.items.filter(i => i.status !== "completed" && i.status !== "failed")
    // Finished ones are rows too, each a way to that thread: "2 finished"
    // said how many but not which, and nothing could be done with it. Live
    // first, then every finished one the helper sends (its newest 24): the
    // list scrolls. It used to stop at eight rows, with no way to the rest.
    readonly property var ended: T3Code.items.filter(i => i.status === "completed" || i.status === "failed")
    readonly property var shownRows: live.concat(ended)
    // Finished ones older than what the helper sends as rows.
    readonly property int beyond: Math.max(0, T3Code.finished - ended.length)
    function dismissFinished() { for (const i of ended.slice()) T3Code.dismiss(i); }
    function ago(iso) {
        // A time that can't be read says nothing ("NaN h ago" was shown for one).
        const at = Date.parse(iso);
        if (!isFinite(at)) return "";
        const m = Math.max(0, Math.round((Date.now() - at) / 60000));
        return m < 1 ? "just now" : m < 60 ? m + " min ago" : Math.round(m / 60) + " h ago";
    }
    function agentName(p) {
        const base = String(p || "").replace(/_\d+$/, "");
        return ({ claudeAgent: "Claude", codex: "Codex", cursor: "Cursor", antigravity: "Antigravity", opencode: "OpenCode", gemini: "Gemini" })[base]
            || (base ? base.charAt(0).toUpperCase() + base.slice(1) : "");
    }

    Column {
        id: col
        x: 20; y: 20
        width: t3.width - 40
        spacing: 14

        // ── The live activity line: identity leads, state trails ─────────
        Item {
            width: parent.width
            height: Theme.sp(26)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "T3"
                size: Theme.tTitle2; weight: Theme.wBold; rounded: true
                color: Theme.cyan
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: T3Code.waiting > 0 ? T3Code.waiting + " need" + (T3Code.waiting === 1 ? "s" : "") + " you · " + T3Code.running + " active"
                    : T3Code.running + " active"
                size: Theme.tCallout; weight: Theme.wSemibold
                color: T3Code.waiting > 0 ? Theme.orange : Theme.cyan
                font.features: ({ "tnum": 1 })
            }
        }

        // ── Empty ────────────────────────────────────────────────────────
        Label {
            visible: t3.live.length === 0 && T3Code.finished === 0
            width: parent.width
            topPadding: 4; bottomPadding: 4
            text: T3Code.alive ? "Nothing running in T3 Code." : "T3 Code isn't open."
            size: Theme.tBody; color: Theme.textTertiary
        }

        // ── Threads ──────────────────────────────────────────────────────
        ListView {
            id: threads
            width: parent.width
            // All of it when it fits (eight rows do at ordinary text). At a large
            // Text size the rows are taller than the island has room for: then
            // it scrolls, and fades where more lies (ScrollFade below).
            // (600 is what the island gives a panel on a 1080p screen. The rest is
            // this panel's own: 76 of padding and gaps, and a header, a "+N more"
            // line and the buttons, 84 together, which grow with the text.)
            height: Math.min(contentHeight, Math.max(Theme.sp(46) * 3, 600 - 76 - Theme.sp(84)))
            interactive: contentHeight > height + 1
            clip: interactive
            boundsBehavior: Flickable.StopAtBounds
            spacing: 2
            // Live threads first, then the finished ones, each one that thread.
            model: ScriptModel { values: t3.shownRows; objectProp: "thread" }
            // One move (choreograph): a swiped row leaves on its spring while the
            // rows below rise into its place, together.
            remove: Transition { PauseAnimation { duration: Theme.reduceMotion ? 0 : Theme.swipeOutMs } }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Theme.reduceMotion ? 0 : Theme.reflowMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut }
            }
            // One highlight for the list, gliding row to row (fluid hover).
            FluidHighlight { parent: threads.contentItem; radius: 12; target: t3.hoverRow }
            delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool waits: modelData.status === "waiting"
                    readonly property bool failed: modelData.status === "failed"
                    readonly property bool done: modelData.status === "completed" || failed
                    readonly property var st: T3.stateOf(modelData)
                    // At a large Text size there is no room for the state beside the
                    // title: it goes under it, and the title may take two lines.
                    readonly property bool stacked: Theme.textScale >= 1.5
                    readonly property string saying: st.word + (st.timed && T3.since(modelData.at, t3.now) ? " " + T3.since(modelData.at, t3.now) : "")
                    readonly property real line: Math.max(Theme.sp(46), words.implicitHeight + Theme.s3)   // its text's own height
                    readonly property var reply: T3Code.replies[modelData.thread] || null
                    readonly property bool previewing: t3.previewOf === modelData.thread && !!reply && reply.text !== ""
                    width: threads.width
                    height: line + (previewing ? preview.height + Theme.s2 : 0)
                    Behavior on height { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    clip: true
                    radius: 12
                    color: "transparent"
                    // A finished thread you've dealt with: swipe it away sideways
                    // (1:1, a flick or past 40 %), or its × — gone from here and
                    // from the capsule's ✓ (T3Code.dismiss); it slides out first.
                    opacity: swipe.fade
                    transform: Translate { x: swipe.offset }
                    SwipeAway {
                        id: swipe
                        enabled: row.done
                        span: row.width
                        onLeaving: T3Code.dismiss(row.modelData)
                    }

                    // State: an orange dot when it needs you, a turning arc while it works.
                    Item {
                        id: state
                        x: 10; y: (row.line - height) / 2
                        width: 14; height: 14
                        Rectangle {
                            visible: row.waits
                            anchors.centerIn: parent
                            width: 8; height: 8; radius: 4
                            color: Theme.orange
                        }
                        // Ended: a check when it finished; a warning when it broke or
                        // was stopped by a limit (a green check sat beside "Failed").
                        Text {
                            textFormat: Text.PlainText
                            visible: row.done
                            anchors.centerIn: parent
                            text: row.st.tone === "done" ? "\u{f012c}" : "\u{f0026}"
                            font.family: Theme.fontGlyph; font.pixelSize: 14
                            color: row.st.tone === "done" ? Theme.green : row.st.tone === "error" ? Theme.red : Theme.orange
                        }
                        // Parked on another thread: a still ring. It isn't working, so nothing turns.
                        Rectangle {
                            visible: row.st.key === "blocked"
                            anchors.centerIn: parent
                            width: 11; height: 11; radius: width / 2
                            color: "transparent"
                            border.width: 1.6; border.color: Qt.rgba(1, 1, 1, 0.28)
                        }
                        Canvas {
                            visible: !row.waits && !row.done && row.st.key !== "blocked"
                            anchors.fill: parent
                            onPaint: {
                                const c = getContext("2d");
                                c.reset(); c.lineWidth = 1.6; c.lineCap = "round";
                                c.strokeStyle = Qt.rgba(1, 1, 1, 0.16); c.beginPath(); c.arc(7, 7, 5.5, 0, Math.PI * 2); c.stroke();
                                c.strokeStyle = Theme.cyan; c.beginPath(); c.arc(7, 7, 5.5, -Math.PI / 2, Math.PI * 0.35); c.stroke();
                            }
                            RotationAnimation on rotation {
                                running: !row.waits && !row.done && row.st.key !== "blocked" && t3.visible && !Theme.reduceMotion
                                from: 0; to: 360; duration: Theme.spinMs; loops: Animation.Infinite
                            }
                        }
                    }
                    // The state, in its own word, at the right edge: a glance down
                    // the list reads them all. It wants you: amber. It broke: red.
                    // Everything else is quiet (the mark on the left has the colour).
                    Label {
                        id: said
                        anchors { right: parent.right; rightMargin: 12 }
                        y: (row.line - height) / 2
                        visible: !row.stacked
                        opacity: row.done && rowHover.hovered ? 0 : 1      // the × takes its place
                        Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
                        text: row.saying
                        size: Theme.tFootnote; weight: row.st.tone === "attention" ? Theme.wSemibold : Theme.wMedium
                        color: row.st.tone === "attention" || row.st.tone === "caution" ? Theme.orange : row.st.tone === "error" ? Theme.red : Theme.textTertiary
                        font.features: ({ "tnum": 1 })
                    }
                    Column {
                        id: words
                        anchors { left: state.right; leftMargin: 12; right: row.stacked ? parent.right : said.left; rightMargin: Theme.s3 }
                        y: (row.line - height) / 2
                        spacing: 2
                        Label {
                            width: parent.width; elide: Text.ElideRight
                            wrapMode: row.stacked ? Text.Wrap : Text.NoWrap
                            maximumLineCount: row.stacked ? 2 : 1
                            text: row.modelData.title || "Untitled thread"
                            size: Theme.tBody; weight: Theme.wSemibold
                            // What is only working steps back; what wants you or has ended leads.
                            color: row.st.tone === "working" || row.st.tone === "idle" ? Theme.textSecondary : Theme.textPrimary
                        }
                        Label {
                            width: parent.width; elide: Text.ElideRight
                            text: [row.stacked ? row.saying : "", t3.agentName(row.modelData.provider), row.modelData.project && row.modelData.project !== "No project" ? row.modelData.project : ""].filter(x => x).join(" · ")
                            visible: text !== ""
                            size: Theme.tFootnote
                            color: !row.stacked ? Theme.textTertiary
                                : row.st.tone === "attention" || row.st.tone === "caution" ? Theme.orange : row.st.tone === "error" ? Theme.red : Theme.textTertiary
                        }
                    }
                    // Its last reply, when the pointer has rested on the row: what it
                    // said, without going there. Not while the screen is shared.
                    Rectangle {
                        id: preview
                        x: state.x + state.width + 12
                        y: row.line
                        width: parent.width - x - 12
                        height: previewCol.implicitHeight + 2 * Theme.s2
                        radius: Theme.r1
                        color: Theme.tileRest
                        opacity: row.previewing ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
                        Column {
                            id: previewCol
                            x: Theme.s3; y: Theme.s2
                            width: parent.width - 2 * Theme.s3
                            spacing: Theme.s1
                            Label {
                                width: parent.width
                                wrapMode: Text.Wrap; maximumLineCount: 5; elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: Notifs.sharing ? "Hidden while sharing your screen" : (row.reply ? row.reply.text : "")
                                size: Theme.tFootnote; lineHeight: 1.3
                                color: Theme.textSecondary
                            }
                            Label {
                                visible: !!row.reply && T3.since(row.reply.at, t3.now) !== ""
                                text: "Last reply · " + (row.reply ? T3.since(row.reply.at, t3.now) : "") + (row.reply && T3.since(row.reply.at, t3.now) !== "now" ? " ago" : "")
                                size: Theme.tCaption; color: Theme.textTertiary
                            }
                        }
                    }
                    Timer {
                        id: rest
                        interval: Theme.tipMs
                        onTriggered: if (rowHover.hovered) { T3Code.wantReply(row.modelData); t3.previewOf = row.modelData.thread; }
                    }
                    HoverHandler {
                        id: rowHover
                        cursorShape: Qt.PointingHandCursor
                        onHoveredChanged: {
                            if (hovered) { t3.hoverRow = row; rest.restart(); }
                            else {
                                if (t3.hoverRow === row) t3.hoverRow = null;
                                rest.stop();
                                if (t3.previewOf === row.modelData.thread) t3.previewOf = "";
                            }
                        }
                    }
                    // That thread, not just the window (T3 Code's own link).
                    TapHandler { onTapped: if (!xHover.hovered) { T3Code.openThread(row.modelData.thread); Island.close(); } }
                    ContextMenu {
                        target: row
                        bounds: t3
                        title: row.modelData.title || "Thread"
                        ContextMenuLabel { text: row.modelData.title || "Untitled thread" }
                        ContextMenuItem { text: "Open in T3 Code"; glyph: "\u{f03cc}"; shortcut: "Click"; onTriggered: { T3Code.openThread(row.modelData.thread); Island.close(); } }
                        ContextMenuItem {
                            text: t3.previewOf === row.modelData.thread ? "Hide last reply" : "Show last reply"
                            glyph: "\u{f0369}"
                            enabled: !Notifs.sharing
                            onTriggered: {
                                if (t3.previewOf === row.modelData.thread) t3.previewOf = "";
                                else { T3Code.wantReply(row.modelData); t3.previewOf = row.modelData.thread; }
                            }
                        }
                        ContextMenuItem { text: "Copy title"; glyph: "\u{f018f}"; onTriggered: Clipboard.copyText(row.modelData.title || "") }
                        ContextMenuSeparator {}
                        ContextMenuItem { text: "Dismiss"; glyph: "\u{f0156}"; visible: row.done; onTriggered: swipe.away(1) }
                        ContextMenuItem { text: "Dismiss all finished (" + t3.ended.length + ")"; visible: t3.ended.length > 1; onTriggered: t3.dismissFinished() }
                    }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: row.modelData.title || "Untitled thread"
                    Accessible.description: T3.spoken(row.modelData)
                        + (t3.agentName(row.modelData.provider) ? ", " + t3.agentName(row.modelData.provider) : "")
                        + (row.modelData.project && row.modelData.project !== "No project" ? ", " + row.modelData.project : "")
                    Accessible.onPressAction: { T3Code.openThread(row.modelData.thread); Island.close(); }
                    // ×: on hover (or with the keyboard focus on the panel), finished rows only.
                    Rectangle {
                        visible: row.done
                        opacity: rowHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
                        anchors { right: parent.right; rightMargin: 10 }
                        y: (row.line - height) / 2
                        width: 24; height: 24; radius: 12
                        color: xHover.hovered ? Theme.pillHover : Theme.pill
                        Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                        Text { anchors.centerIn: parent; text: "\u{f0156}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.tSub; color: Theme.textSecondary }
                        HoverHandler { id: xHover; margin: 8 }
                        TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: swipe.away(1) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Dismiss " + (row.modelData.title || "thread")
                        Accessible.onPressAction: swipe.away(1)
                    }
                }
        }
        ScrollFade { flickable: threads }
        ScrollHint { flickable: threads; inside: true }

        Label {
            visible: t3.beyond > 0
            leftPadding: 10
            text: "+" + t3.beyond + " older in T3 Code"
            size: Theme.tFootnote; color: Theme.textTertiary
        }

        // The way on: T3 itself, or every agent you run (kittymux's too) in
        // the notch's Agents panel.
        Row {
            width: parent.width
            spacing: 8
            Button {
                width: (parent.width - 8) / 2
                text: "Open T3 Code"
                onClicked: { T3Code.focus(); Island.close(); }
            }
            Button {
                width: (parent.width - 8) / 2
                text: "All agents"
                onClicked: Island.open("agents", Island.screen, "pointer", "island")
            }
        }
    }
}
