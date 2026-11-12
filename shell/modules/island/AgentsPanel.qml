// Every agent you run, grown out of the island (click an agent's mark on the
// notch): kittymux's panes and T3 Code's threads in one list, the one waiting
// on you first. Each row says who (the agent's mark), what (the tab or
// thread), where (the project), on what (the model and its effort) and how
// it's doing; one waiting on you carries its question. A row takes you there:
// that kitty pane, that T3 thread.
//
//   Agents                               1 needs you · 2 working
//   ✳ Fix notch alerts                                   3m
//     Needs you · rice · Opus 5.5 high
//     Allow edit to Notifs.qml?
//   ✳ Handoff sidebar rebuild plan                       1m
//     Working · kittymux · Opus 5.5 high
//   ◇ Monitor sharpness                                  12m
//     Done · T3 · Grok 4.7 high
//   [ Usage ]  [ All agents ]
//
//   ↑ ↓ choose · ↵ go · Esc back
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

FocusScope {
    id: ap
    focus: true
    implicitWidth: 440
    implicitHeight: col.implicitHeight + 36

    property int sel: 0
    property bool keyboard: false

    // ── What runs where, on what ────────────────────────────────────────
    // The model a kitty pane runs is in its agent's own session log
    // (bin/rice-agent-models); asked when this opens and every 30 s while
    // it's open, never while it's closed.
    property var models: ({})
    readonly property var modelArgs: Kittymux.running.filter(r => r.where).map(r => r.agent + ":" + r.where)
    Process {
        id: modelsProc
        command: [Paths.bin + "/rice-agent-models"].concat(ap.modelArgs)
        stdout: StdioCollector {
            onStreamFinished: { try { ap.models = JSON.parse(text) || {}; } catch (e) {} }
        }
    }
    function askModels() { if (modelArgs.length && !modelsProc.running) modelsProc.running = true; }
    Component.onCompleted: askModels()
    Timer { interval: 30000; repeat: true; running: ap.visible; onTriggered: ap.askModels() }

    // "claude-opus-5-5" → "Opus 5.5", "grok-4.7" → "Grok 4.7", "gpt-6.1-sol" → "GPT-6.1 Sol".
    function modelName(m) {
        let s = String(m || "").trim();
        if (!s) return "";
        let c = /^claude-([a-z]+)-(\d+)-(\d+)/i.exec(s);
        if (c) return c[1].charAt(0).toUpperCase() + c[1].slice(1) + " " + c[2] + "." + c[3];
        c = /^gpt-([\d.]+)(?:-(.+))?$/i.exec(s);
        if (c) return "GPT-" + c[1] + (c[2] ? " " + c[2].charAt(0).toUpperCase() + c[2].slice(1) : "");
        return s.split("-").map(p => p.charAt(0).toUpperCase() + p.slice(1)).join(" ");
    }
    function on(model, effort) { const n = modelName(model); return n ? n + (effort ? " " + effort : "") : ""; }
    function ago(ms) {
        if (!ms) return "";
        const m = Math.max(0, Math.round((Date.now() - ms) / 60000));
        return m < 1 ? "now" : m < 60 ? m + "m" : m < 1440 ? Math.floor(m / 60) + "h" : Math.floor(m / 1440) + "d";
    }
    function t3Agent(p) {
        const base = String(p || "").replace(/_\d+$/, "");
        return ({ claudeAgent: "claude", codex: "codex", cursor: "cursor", antigravity: "antigravity", opencode: "opencode", gemini: "gemini", grok: "grok" })[base] || base;
    }

    // ── One list: kittymux panes, then T3 threads, by how much they need you ─
    readonly property var rows: {
        const out = [];
        const events = Kittymux.attention || [];
        for (const r of Kittymux.running) {
            // Its unread event, if any: going there through it marks it read.
            const ev = events.find(e => String(e.pid) === String(r.pid) && String(e.w) === r.w);
            const m = ap.models[r.agent + ":" + r.where] || {};
            const state = r.needs || (ev && ev.severity === "needs-you") ? "needs"
                : r.working ? "working" : r.state === "error" ? "error" : r.state === "limited" ? "limited"
                : r.state === "done" ? "done" : "idle";
            out.push({
                key: "k" + r.key, src: "kitty", agent: r.agent, title: r.title,
                where: r.project || String(r.where || "").replace(/^.*\//, ""),
                model: ap.on(m.model, m.effort), state: state, status: r.status,
                question: r.question || (ev && ev.severity === "needs-you" ? Notifs.readable(ev.body || "") : ""),
                t: (r.since || 0) * 1000, event: ev ? ev.id : "", action: r.action
            });
        }
        for (const i of T3Code.items) {
            const st = i.status === "waiting" ? "needs" : i.status === "completed" ? "done" : i.status === "failed" ? "error" : "working";
            out.push({
                key: "t" + i.thread, src: "t3", agent: ap.t3Agent(i.provider), title: i.title || "Untitled thread",
                where: "T3" + (i.project && i.project !== "No project" ? " · " + i.project : ""),
                model: ap.on(i.model, i.effort), state: st, status: "", question: "",
                t: i.at ? Date.parse(i.at) : 0, thread: i.thread
            });
        }
        const rank = { needs: 0, error: 1, limited: 2, working: 3, done: 4, idle: 5 };
        return out.sort((a, b) => (rank[a.state] - rank[b.state]) || (b.t - a.t));
    }
    onRowsChanged: sel = Math.min(sel, Math.max(0, rows.length - 1))
    readonly property int needN: rows.filter(r => r.state === "needs").length
    readonly property int workN: rows.filter(r => r.state === "working").length

    function go(r) {
        if (!r) return;
        Island.close();
        if (r.src === "t3") T3Code.openThread(r.thread);
        else if (r.event) Kittymux.jumpEvent(r.event);
        else Kittymux.act(r.action);
    }
    function word(s) {
        return ({ needs: "Needs you", working: "Working", error: "Error", limited: "Hit a limit", done: "Done", idle: "Idle" })[s] || "";
    }
    function tone(s) {
        return s === "needs" || s === "limited" ? Theme.orange : s === "error" ? Theme.red : s === "done" ? Theme.green : s === "working" ? Theme.cyan : Theme.textTertiary;
    }

    Keys.onPressed: e => {
        if ([Qt.Key_Down, Qt.Key_Up, Qt.Key_Return, Qt.Key_Enter].indexOf(e.key) >= 0) keyboard = true;
        if (e.key === Qt.Key_Down) sel = Math.min(rows.length - 1, sel + 1);
        else if (e.key === Qt.Key_Up) sel = Math.max(0, sel - 1);
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) go(rows[sel]);
        else return;
        list.positionViewAtIndex(sel, ListView.Contain);
        e.accepted = true;
    }

    Column {
        id: col
        x: 18; y: 18
        width: ap.width - 36
        spacing: 10

        // ── The live activity line: what it is, then how they're doing ──
        Item {
            width: parent.width
            height: 24
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Agents"
                size: Theme.tTitle3; weight: Theme.wSemibold
            }
            Label {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: [ap.needN ? ap.needN + " need" + (ap.needN === 1 ? "s" : "") + " you" : "", ap.workN ? ap.workN + " working" : ""].filter(x => x).join(" · ")
                size: Theme.tFootnote; weight: Theme.wMedium
                color: ap.needN ? Theme.orange : Theme.textTertiary
                font.features: ({ "tnum": 1 })
            }
        }

        // ── Empty: say so, and how to start one ─────────────────────────
        Column {
            visible: ap.rows.length === 0
            width: parent.width
            topPadding: 8; bottomPadding: 8
            spacing: 4
            Label { text: "No agents running"; size: Theme.tSub; color: Theme.textSecondary }
            Label {
                text: !Kittymux.available && !T3Code.alive ? "Neither kittymux nor T3 Code is running."
                    : "Super+A, then “claude” or “codex”, starts one here."
                size: Theme.tFootnote; color: Theme.textTertiary
            }
        }

        ListView {
            id: list
            visible: ap.rows.length > 0
            width: parent.width
            height: Math.min(contentHeight, 420)
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: ScriptModel { values: ap.rows; objectProp: "key" }
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool needs: modelData.state === "needs"
                width: list.width
                height: inner.implicitHeight + 20
                radius: Theme.r2
                color: rowHover.hovered || ap.sel === index ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.title + ", " + ap.word(modelData.state) + (modelData.where ? ", " + modelData.where : "") + (modelData.model ? ", " + modelData.model : "")
                Accessible.description: modelData.question || ""
                Accessible.selected: ap.sel === index
                Rectangle {
                    visible: ap.keyboard && ap.sel === row.index
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.6)
                    z: 100
                }

                // Who: the agent's mark, its state on the corner (the words say it too).
                Item {
                    x: 10; y: 12
                    width: 30; height: 30
                    Rectangle { anchors.fill: parent; radius: 9; color: Qt.rgba(1, 1, 1, 0.06) }
                    Image {
                        id: mark
                        anchors.centerIn: parent
                        width: 18; height: 18
                        sourceSize: Qt.size(36, 36)
                        source: Kittymux.brand(row.modelData.agent)
                        smooth: true; mipmap: true
                    }
                    Text {
                        visible: mark.status !== Image.Ready
                        anchors.centerIn: parent
                        text: "\u{f06a9}"
                        font.family: Theme.fontGlyph; font.pixelSize: 15
                        color: Theme.textSecondary
                    }
                    Rectangle {
                        visible: row.modelData.state !== "idle"
                        x: parent.width - 7; y: -2
                        width: 9; height: 9; radius: 4.5
                        color: ap.tone(row.modelData.state)
                        border.width: 2; border.color: "#000000"
                    }
                }
                Column {
                    id: inner
                    x: 52; y: 10
                    width: parent.width - 62
                    spacing: 2
                    Item {
                        width: parent.width
                        height: title.implicitHeight
                        Label {
                            id: title
                            width: parent.width - age.implicitWidth - 8
                            elide: Text.ElideRight
                            text: row.modelData.title
                            size: Theme.tBody; weight: Theme.wSemibold
                        }
                        Label {
                            id: age
                            anchors { right: parent.right; baseline: title.baseline }
                            text: ap.ago(row.modelData.t)
                            size: Theme.tFootnote; color: Theme.textTertiary
                            font.features: ({ "tnum": 1 })
                        }
                    }
                    Label {
                        width: parent.width
                        elide: Text.ElideRight
                        // State first, in its colour; then where and on what, quieter.
                        textFormat: Text.StyledText
                        text: "<font color='" + ap.tone(row.modelData.state) + "'>" + ap.word(row.modelData.state) + "</font>"
                            + [row.modelData.where, row.modelData.model].filter(x => x).map(x => " · " + Notifs.styledSafe(x)).join("")
                        size: Theme.tFootnote; color: Theme.textSecondary
                    }
                    Label {
                        visible: row.needs && row.modelData.question !== ""
                        width: parent.width
                        topPadding: 2
                        wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                        text: row.modelData.question
                        size: Theme.tSub; lineHeight: 1.3; color: Theme.textPrimary
                    }
                }
                HoverHandler {
                    id: rowHover
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: if (hovered) { ap.keyboard = false; ap.sel = row.index; }
                }
                TapHandler { onTapped: ap.go(row.modelData) }
            }
        }

        // The way on: how much they've got left, or the full list with recent ones to resume.
        Row {
            width: parent.width
            spacing: 8
            PillButton {
                width: (parent.width - 8) / 2
                text: "Usage"
                onClicked: Island.open("usage", Island.screen, "pointer")
            }
            PillButton {
                width: (parent.width - 8) / 2
                text: "All agents"
                onClicked: { Island.close(); Notifs.toggleCenter("agents", "pointer", Island.screen); }
            }
        }
    }
}
