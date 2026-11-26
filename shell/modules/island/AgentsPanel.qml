// Every agent you run, grown out of the island (click an agent's mark on the
// notch): kittymux's panes and T3 Code's threads in one list, the one waiting
// on you first. Each row says who (the agent's mark), what (the tab or
// thread), where (the project), on what (the model and its effort) and how
// it's doing; one waiting on you carries its question. A row takes you there:
// that kitty pane, that T3 thread.
//
//   Agents                               1 needs you · 2 working
//   ✳ Fix notch alerts                                   3m
//     Needs you · kuwai · Opus 5.5 high
//     Allow edit to Notifs.qml?
//   ✳ Handoff sidebar rebuild plan                       1m
//     Working · kittymux · Opus 5.5 high
//   ◇ Monitor sharpness                                  12m
//     Done · T3 · Grok 4.7 high
//   [ Usage ]  [ Mark all read ]           closed conversations last, to reopen
//
//   ↑ ↓ choose · ↵ go · ⌫ remove (finished, closed) · A all read · U usage · Esc back
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.config
import qs.components
import qs.components.ui
import qs.services
import "../../services/t3.mjs" as T3
import "../../services/agents.mjs" as Ag

FocusScope {
    id: ap
    HoverHandler { id: panelHover }
    focus: true
    implicitWidth: Theme.panelS
    implicitHeight: col.implicitHeight + 36

    property int sel: 0
    property bool keyboard: false
    property Item hoverRow: null          // the row under the pointer (the highlight goes there)

    // ── What runs where, on what ────────────────────────────────────────
    // The model a kitty pane runs is in its agent's own session log
    // (bin/kuwai-agent-models); asked when this opens and every 30 s while
    // it's open, never while it's closed.
    property var models: ({})
    readonly property var modelArgs: Kittymux.running.filter(r => r.where).map(r => r.agent + ":" + r.where)
    Process {
        id: modelsProc
        command: [Paths.bin + "/kuwai-agent-models"].concat(ap.modelArgs)
        stdout: StdioCollector {
            onStreamFinished: { try { ap.models = JSON.parse(text) || {}; } catch (e) {} }
        }
    }
    function askModels() { if (modelArgs.length && !modelsProc.running) modelsProc.running = true; }
    Binding { target: Providers; property: "agentsShown"; value: ap.visible }
    property var costs: null
    property int budget: Settings.agentBudget
    readonly property bool budgeted: budget > 0
    readonly property var t3Threads: T3Code.liveItems.map(i => String(i.thread || "")).filter(t => t)
    Process {
        id: costProc
        command: [Paths.bin + "/kuwai-agent-cost"].concat(ap.t3Threads)
        stdout: StdioCollector {
            onStreamFinished: { try { const v = JSON.parse(text); if (v && v.available) ap.costs = v; } catch (e) {} }
        }
    }
    Timer { interval: Theme.panelPollMs * 12; repeat: true; running: ap.visible && ap.budgeted; triggeredOnStart: true; onTriggered: if (!costProc.running) costProc.running = true }
    function money(v) { return v >= 100 ? "$" + Math.round(v) : "$" + v.toFixed(2); }
    function costOf(thread) {
        const c = budgeted && costs && thread ? costs.threads[thread] : null;
        return c && c.cost >= 0.01 ? money(c.cost) + (c.priced ? "" : "+") : "";
    }
    readonly property string budgetLine: !budgeted || !costs ? ""
        : "Today ~" + money(costs.today.cost) + (costs.today.unpriced > 0 ? "+" : "") + " of your $" + budget + " budget"
    readonly property bool overBudget: budgeted && !!costs && costs.today.cost > budget
    Component.onCompleted: askModels()
    Timer { interval: 30000; repeat: true; running: ap.visible; onTriggered: ap.askModels() }
    property real now: Date.now()
    Timer { interval: 30000; repeat: true; running: ap.visible; triggeredOnStart: true; onTriggered: ap.now = Date.now() }
    property var t3Answers: ({})
    function setT3Answer(id, v) { const n = Object.assign({}, t3Answers); n[id] = v; t3Answers = n; }
    function answerT3(r, decision) {
        if (!r || !r.request || (t3Answers[r.request.id] || {}).busy) return;
        setT3Answer(r.request.id, { busy: true, done: "", why: "" });
        t3Answer.createObject(ap, { asked: { id: r.request.id, decision: decision },
            command: [Paths.bin + "/kuwai-t3-answer", r.thread, r.request.id, decision] }).running = true;
    }
    Component {
        id: t3Answer
        Process {
            id: one
            property var asked: null
            onExited: destroy(1000)
            stdout: StdioCollector {
                onStreamFinished: {
                    const p = one.asked;
                    let r = {};
                    try { r = JSON.parse(text); } catch (e) {}
                    ap.setT3Answer(p.id, { busy: false, done: r.ok ? p.decision : "",
                        why: r.ok ? "" : r.why === "scope" ? "T3's token for Kuwai can't answer yet (it needs orchestration:operate). Open it in T3."
                            : r.why === "gone" ? "Already answered." : "T3 didn't take it. Open it in T3." });
                    if (r.ok) T3Code.read();
                }
            }
        }
    }
    property bool inStrip: false
    readonly property string headerMeta: [needN ? needN + " need" + (needN === 1 ? "s" : "") + " you" : "", workN ? workN + " working" : ""].filter(x => x).join(" · ")
    readonly property color headerMetaTone: needN ? Theme.orange : Theme.textTertiary
    property var ports: []
    Process {
        id: portsProc
        command: [Paths.bin + "/kuwai-ports"]
        stdout: StdioCollector {
            onStreamFinished: { try { const v = JSON.parse(text); if (JSON.stringify(v) !== JSON.stringify(ap.ports)) ap.ports = v; } catch (e) {} }
        }
    }
    Timer { interval: Theme.panelPollMs; repeat: true; running: ap.visible && Settings.agentServers; triggeredOnStart: true; onTriggered: if (!portsProc.running) portsProc.running = true }

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
    function esc(t) { return String(t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
    function on(model, effort) { const n = modelName(model); return n ? n + (effort ? " " + effort : "") : ""; }
    function ago(ms) {
        if (!ms) return "";
        const m = Math.max(0, Math.round((ap.now - ms) / 60000));
        return m < 1 ? "now" : m < 60 ? m + "m" : m < 1440 ? Math.floor(m / 60) + "h" : Math.floor(m / 1440) + "d";
    }
    function t3Agent(p) { return Agents.t3Agent(p); }

    // ── One list: kittymux panes, then T3 threads, by how much they need you ─
    readonly property var sections: [...new Set(rows.map(r => r.section))]
    readonly property var rows: {
        const out = [];
        for (const x of Agents.sessions) {
            const r = x.pane && x.pane.raw ? x.pane.raw : null, i = x.t3, d = x.hook;
            const ev = x.event ? Kittymux.eventById(x.event) : null;
            const m = r ? ap.models[r.agent + ":" + r.where] || {} : {};
            const back = x.state === "limited" ? Ag.until(x.reset || (i ? Ag.backAt(Limits.windows, Agents.providerId(i.provider), ap.now) : 0), ap.now) : "";
            out.push({
                section: x.section,
                word: x.stateKey === "blocked" ? (i && i.held ? "Waiting on background work" : x.src === "t3" ? "Waiting on another thread" : "Waiting")
                    : back ? "Limit · back in " + back
                    : ({ approval: "Approval", question: "Question", request: "Request", woke: "Woke", goal: "Goal" })[x.stateKey] || "",
                stateKey: x.stateKey || x.state,
                key: x.key, src: x.src, agent: x.agent, who: i ? Providers.name(i.provider) : "", title: x.title || (x.src === "t3" ? "Untitled thread" : Kittymux.agentLabel(x.agent)),
                where: r ? r.project || String(r.where || "").replace(/^.*\//, "")
                    : i ? (i.project && i.project !== "No project" ? i.project : "") : d ? d.project || "" : "",
                model: m.model ? ap.on(m.model, m.effort)
                    : i ? (Providers.modelName(i.provider, i.model) ? Providers.modelName(i.provider, i.model) + (i.effort ? " " + i.effort : "") : ap.on(i.model, i.effort))
                    : d ? ap.on(d.model, "") : "",
                modelId: m.model || (i && i.model) || (d && d.model) || "",
                state: x.state, status: r ? r.status : "", ctx: m.context || (i && i.ctx) || 0, win: m.window || (i && i.win) || 0,
                warm: i && (x.state === "done" || x.state === "idle") ? Ag.warm(i.cacheUntil, ap.now) : "",
                cost: i ? ap.costOf(i.thread) : "",
                room: i && x.state === "limited" ? Providers.roomFor(i.provider) : "", reply: m.reply || "", steps: m.steps || [],
                question: x.question || (ev && ev.severity === "needs-you" ? Notifs.readable(ev.body || "") : ""),
                request: i ? i.request || null : null,
                t: x.t, event: x.event, action: x.action, thread: x.thread, item: i,
                windowClass: x.windowClass, desktopId: x.desktopId, raw: r || d, sources: x.sources
            });
        }
        // Closed conversations to reopen (kittymux asks before resuming one),
        // last: what the center's Agents tab had that this list didn't.
        for (const r of Kittymux.recent) {
            out.push({
                section: "Recent",
                stateKey: "",
                key: "r" + r.hideKey, src: "recent", agent: r.agent, title: r.title,
                where: r.project || String(r.where || "").replace(/^.*\//, ""),
                model: "", state: "recent", status: r.status || "", question: "", t: 0, action: r.action, hideKey: r.hideKey, raw: r
            });
        }
        const rank = { needs: 0, error: 1, limited: 2, working: 3, done: 4, idle: 5, recent: 6 };
        const secOrder = { "T3 Code": 0, "Terminal": 1, "Desktop": 2, "Recent": 3 };
        const secUrgent = {};
        for (const row of out) {
            const r = rank[row.state] ?? 9;
            if (secUrgent[row.section] === undefined || r < secUrgent[row.section]) secUrgent[row.section] = r;
        }
        return out.sort((a, b) => {
            if (a.section !== b.section) {
                if (a.section === "Recent") return 1;
                if (b.section === "Recent") return -1;
                const ua = secUrgent[a.section] <= 1 ? 0 : 1;
                const ub = secUrgent[b.section] <= 1 ? 0 : 1;
                if (ua !== ub) return ua - ub;
                return (secOrder[a.section] ?? 9) - (secOrder[b.section] ?? 9);
            }
            return (rank[a.state] - rank[b.state]) || (a.state === "needs" ? (a.t || Infinity) - (b.t || Infinity) : b.t - a.t);
        });
    }
    onRowsChanged: {
        sel = Math.min(sel, Math.max(0, rows.length - 1));
        if (list.followTop) Qt.callLater(() => list.positionViewAtBeginning());
    }
    readonly property int needN: Agents.tally.needs
    readonly property int workN: Agents.tally.working

    // What can be put away from here: a finished T3 thread, a finished kitty
    // agent's unread event, a kitty agent's limit or error (until its state
    // changes), a closed conversation. Working and waiting ones can't:
    // they're live, and swiping one away would hide something still on.
    function canDismiss(r) {
        return !!r && ((r.src === "t3" && (r.state === "done" || r.state === "error")) || r.src === "recent"
            || (r.src === "desktop" && (r.state === "done" || r.state === "error" || r.state === "limited"))
            || (r.src === "kitty" && (r.state === "limited" || r.state === "error")));
    }
    function dismiss(r) {
        if (!canDismiss(r)) return;
        if (r.src === "t3") T3Code.dismiss(r.item);
        else if (r.src === "desktop") Agents.dismissDesktop(r.desktopId);
        else if (r.src === "recent") Kittymux.hideRecent(r.raw);
        else {
            if (r.event) Kittymux.ack(r.event);
            if (r.state === "limited" || r.state === "error") Kittymux.quiet(r.raw);
        }
    }
    function go(r) {
        if (!r) return;
        Island.close();
        if (r.src === "t3") T3Code.openThread(r.thread);
        else if (r.src === "desktop") Agents.focusDesktop(r);
        else if (r.event) Kittymux.jumpEvent(r.event);
        else Kittymux.act(r.action);
    }
    function fill(r) {
        if (!r || !r.ctx) return "";
        if (r.win > 0) {
            const p = r.ctx / r.win;
            return p >= 0.7 ? "<font color='" + (p >= 0.9 ? Theme.orange : Theme.textSecondary) + "'>Context " + Math.round(p * 100) + "%</font>" : "";
        }
        return r.ctx >= 140000 ? "Context " + Math.round(r.ctx / 1000) + "K" : "";
    }
    function word(s) {
        return ({ needs: "Needs you", working: "Working", error: "Error", limited: "Hit a limit", done: "Done", idle: "Idle", recent: "Closed · reopen" })[s] || "";
    }
    function tone(s) {
        return s === "needs" ? Theme.orange : s === "error" || s === "limited" ? Theme.red : s === "done" ? Theme.green : s === "working" ? Theme.cyan : Theme.textTertiary;
    }
    function brandOf(agent) { return Theme.brandTint[String(Kittymux.brand(agent)).replace(/^.*\//, "").replace(/\.svg$/, "")] || Theme.accent; }
    function pillText(r) {
        const age = ago(r.t);
        if (r.state === "done") return "Done" + (age && age !== "now" ? " " + age : "");
        if (r.state === "working") return "Working";
        if (r.state === "idle") return age || "Idle";
        return r.word || word(r.state);
    }
    function dotOf(r) { return r.state === "working" ? brandOf(r.agent) : tone(r.state); }

    Keys.onPressed: e => {
        if ([Qt.Key_Down, Qt.Key_Up, Qt.Key_Return, Qt.Key_Enter].indexOf(e.key) >= 0) keyboard = true;
        // Menu / Shift+F10: the chosen row's menu (what a right-click shows).
        if (e.key === Qt.Key_Menu || (e.key === Qt.Key_F10 && (e.modifiers & Qt.ShiftModifier))) {
            const it = list.itemAtIndex(sel);
            if (it) { list.positionViewAtIndex(sel, ListView.Contain); it.menu.popup(); }
            e.accepted = true;
            return;
        }
        if (e.key === Qt.Key_Down) sel = Math.min(rows.length - 1, sel + 1);
        else if (e.key === Qt.Key_Up) sel = Math.max(0, sel - 1);
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) go(rows[sel]);
        else if (e.key === Qt.Key_U) { Island.open("usage", Island.screen, "key"); }
        else if (e.key === Qt.Key_A) Kittymux.ackAll();
        else if ((e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) && rows[sel]) {
            if (canDismiss(rows[sel])) dismiss(rows[sel]);
            else if (rows[sel].event) Kittymux.ack(rows[sel].event);     // a waiting one: marked read, still listed
        }
        else return;
        list.positionViewAtIndex(sel, ListView.Contain);
        list.followTop = sel === 0;
        e.accepted = true;
    }

    Column {
        id: col
        x: 18; y: ap.inStrip ? Theme.s2 : 18
        width: ap.width - 36
        spacing: 10

        // ── The live activity line: what it is, then how they're doing ──
        Item {
            id: head
            visible: !ap.inStrip
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
                tabular: true
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
                width: parent.width
                wrapMode: Text.Wrap
                text: !Kittymux.available && !T3Code.alive ? "Neither kittymux nor T3 Code is running."
                    : "Super+A, then “claude” or “codex”, starts one here."
                size: Theme.tFootnote; color: Theme.textTertiary
            }
        }

        ListView {
            id: list
            visible: ap.rows.length > 0
            width: parent.width
            readonly property real others: (head.visible ? head.height + col.spacing : 0) + footRow.height + (portsCard.visible ? portsCard.height : 0)
                + (keyHints.visible ? keyHints.height : 0) + (health.visible ? health.height + col.spacing : 0)
                + (budgetNote.visible ? budgetNote.height + col.spacing : 0)
                + col.spacing * (1 + (portsCard.visible ? 1 : 0) + (keyHints.visible ? 1 : 0))
            readonly property real room: Theme.panelMaxH - (ap.inStrip ? 34 : 0) - col.y - 18
            height: Math.min(contentHeight, Math.max(Theme.sp(96), room - others))
            clip: true
            spacing: Theme.s2
            boundsBehavior: Flickable.StopAtBounds
            property bool followTop: true
            onMovementEnded: followTop = atYBeginning
            model: ScriptModel { values: ap.rows; objectProp: "key" }
            // One move (choreograph): a swiped row's spring carries it out while
            // the rows below rise into its place, together, not one after the other.
            remove: Transition { PauseAnimation { duration: Theme.reduceMotion ? 0 : Theme.swipeOutMs } }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Theme.reduceMotion ? 0 : Theme.reflowMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut }
            }
            // One highlight for the list (fluid hover): it glides from row to row
            // under the pointer on the fast spring, and is the keyboard's ring.
            FluidHighlight {
                parent: list.contentItem
                radius: Theme.r3
                target: ap.keyboard ? (list.itemAtIndex(ap.sel) ? list.itemAtIndex(ap.sel).plate : null) : ap.hoverRow
                ring: ap.keyboard
            }
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool needs: modelData.state === "needs"
                readonly property bool firstOfGroup: index === 0 || (ap.rows[index - 1] || {}).section !== modelData.section
                readonly property real headH: firstOfGroup && ap.sections.length > 1 ? Theme.sp(30) : 0
                readonly property alias plate: plate
                width: list.width
                height: headH + lrow.implicitHeight + Theme.s2 * 2
                Row {
                    visible: row.headH > 0
                    x: Theme.s1
                    y: row.headH - height - 8
                    spacing: 6
                    Image {
                        visible: row.modelData.section === "T3 Code" && status === Image.Ready
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14
                        sourceSize: Qt.size(28, 28)
                        source: row.modelData.section === "T3 Code" && row.headH > 0 ? NotifAdapters.entryIcon("t3code") : ""
                        smooth: true; mipmap: true
                    }
                    Text {
                        visible: row.modelData.section === "Terminal" || row.modelData.section === "Desktop"
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: row.modelData.section === "Desktop" ? "\u{f0379}" : "\u{f018d}"
                        font.family: Theme.fontGlyph; font.pixelSize: Theme.tSub
                        color: Theme.textTertiary
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.section
                        size: Theme.tFootnote; weight: Theme.wSemibold
                        color: Theme.textSecondary
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(ap.rows.filter(r => r.section === row.modelData.section).length)
                        size: Theme.tFootnote; weight: Theme.wMedium; rounded: true
                        color: Theme.textTertiary
                        tabular: true
                    }
                }
                Rectangle {
                    id: plate
                    y: row.headH
                    width: parent.width
                    height: parent.height - row.headH
                    radius: Theme.r3
                    color: Theme.card
                    border.width: 1
                    border.color: Theme.cardEdge
                    AmbientGlow {
                        visible: row.modelData.state === "working" && Settings.agentGlow
                        tint: ap.brandOf(row.modelData.agent)
                        radius: Theme.r3
                        breathing: true
                        calm: panelHover.hovered
                    }
                }
                // Swipe away sideways (or ×, or ⌫ on the selected row): it slides
                // out, then goes; the rest close the gap.
                readonly property bool dismissable: ap.canDismiss(modelData)
                readonly property var menu: rowMenu
                readonly property var askRaw: modelData.src === "kitty" ? modelData.raw : null
                ContextMenu {
                    id: rowMenu
                    target: row
                    bounds: ap
                    title: row.modelData.title
                    ContextMenuLabel { text: row.modelData.title }
                    ContextMenuItem {
                        text: row.modelData.src === "t3" ? "Open in T3 Code" : row.modelData.src === "desktop" ? "Focus " + Kittymux.agentLabel(row.modelData.agent) : row.modelData.src === "recent" ? "Reopen" : "Go to it"
                        glyph: "\u{f03cc}"; shortcut: "↵"
                        onTriggered: ap.go(row.modelData)
                    }
                    // A kitty agent asking permission: answer it from here too.
                    ContextMenuItem { text: "Allow"; glyph: "\u{f012c}"; visible: !!row.askRaw && Kittymux.canAnswer(row.askRaw); onTriggered: Kittymux.answer(row.askRaw, "allow") }
                    ContextMenuItem { text: "Deny"; variant: "destructive"; visible: !!row.askRaw && Kittymux.canAnswer(row.askRaw); onTriggered: Kittymux.answer(row.askRaw, "deny") }
                    ContextMenuItem { text: "Copy title"; glyph: "\u{f018f}"; onTriggered: Clipboard.copyText(row.modelData.title || "") }
                    ContextMenuSeparator {}
                    ContextMenuItem { text: "Mark read"; visible: !!row.modelData.event && !row.dismissable; onTriggered: Kittymux.ack(row.modelData.event) }
                    ContextMenuItem { text: row.modelData.src === "recent" ? "Forget" : "Remove from here"; glyph: "\u{f0156}"; shortcut: "⌫"; visible: row.dismissable; onTriggered: swipe.away(1) }
                    ContextMenuItem { text: "Mark all read"; shortcut: "A"; visible: (Kittymux.attention || []).length > 1; onTriggered: Kittymux.ackAll() }
                }
                opacity: swipe.fade
                transform: Translate { x: swipe.offset }
                SwipeAway { id: swipe; enabled: row.dismissable; span: row.width; onLeaving: ap.dismiss(row.modelData) }
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.title + ", " + (modelData.word || ap.word(modelData.state)) + (modelData.where ? ", " + modelData.where : "") + (modelData.model ? ", " + modelData.model : "") + (modelData.win && modelData.ctx / modelData.win >= 0.7 ? ", context " + Math.round(modelData.ctx / modelData.win * 100) + " percent full" : "")
                Accessible.description: modelData.question || ""
                Accessible.selected: ap.sel === index
                // The keyboard's ring is the list's FluidHighlight (ring: keyboard).

                // The shared row (components/ListRow): who (the agent's mark, its
                // state on the corner; the words say it too), the title, the state
                // in its colour then where and on what, its age at the right edge,
                // and what it asks under it.
                ListRow {
                    id: lrow
                    y: row.headH + Theme.s2
                    width: parent.width
                    lead: AgentMark {
                        anchors.fill: parent
                        agent: row.modelData.agent
                        name: row.modelData.who || Kittymux.agentLabel(row.modelData.agent)
                        model: row.modelData.modelId || ""
                        t3: row.modelData.src === "t3"
                    }
                    title: row.modelData.title
                    trail: StatusPill { text: ap.pillText(row.modelData); dot: ap.dotOf(row.modelData) }
                    // The × takes its place on hover (a removable row).
                    trailOpacity: row.dismissable && rowHover.hovered ? 0 : 1
                    subFormat: Text.StyledText
                    sub: [row.modelData.who || Kittymux.agentLabel(row.modelData.agent), row.modelData.where, row.modelData.model]
                        .filter(x => x).map(x => ap.esc(x)).join(" · ")
                        + (ap.fill(row.modelData) ? " · " + ap.fill(row.modelData) : "")
                        + (row.modelData.warm ? " · " + row.modelData.warm : "")
                        + (row.modelData.cost ? " · " + row.modelData.cost : "")
                        + (row.modelData.room ? " · " + ap.esc(row.modelData.room) + " has room" : "")
                    subColor: Theme.textSecondary
                    Label {
                        readonly property var ask: row.modelData.src === "kitty" ? Kittymux.askFor(row.modelData.raw)
                            : row.modelData.src === "t3" && row.modelData.request && row.modelData.request.prompt ? { what: row.modelData.request.prompt } : null
                        visible: row.needs && text !== ""
                        width: parent.width
                        textFormat: Text.PlainText
                        wrapMode: ask ? Text.WrapAnywhere : Text.Wrap
                        maximumLineCount: ask ? 40 : 3
                        elide: ask ? Text.ElideNone : Text.ElideRight
                        text: ask ? String(ask.what || "") : row.modelData.question
                        size: Theme.tSub; lineHeight: 1.3; color: Theme.textPrimary
                    }
                    Column {
                        visible: row.modelData.state === "working" && (row.modelData.steps || []).length > 0
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: row.modelData.steps || []
                            Row {
                                id: stepRow
                                required property string modelData
                                required property int index
                                readonly property bool newest: index === (row.modelData.steps || []).length - 1
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: stepRow.newest ? "\u{f0142}" : "\u{f012c}"
                                    font.family: Theme.fontGlyph; font.pixelSize: Theme.tFootnote
                                    color: stepRow.newest ? ap.brandOf(row.modelData.agent) : Theme.textTertiary
                                }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: lrow.width - Theme.rowInset * 2 - Theme.rowMark - Theme.rowGap - 20
                                    elide: Text.ElideRight
                                    text: stepRow.modelData
                                    size: Theme.tSub
                                    color: stepRow.newest ? Theme.textSecondary : Theme.textTertiary
                                }
                            }
                        }
                    }
                    Label {
                        visible: row.modelData.state === "done" && !!row.modelData.reply
                        width: parent.width
                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        text: row.modelData.reply ? T3.excerpt(row.modelData.reply) : ""
                        size: Theme.tSub; lineHeight: 1.3; color: Theme.textTertiary
                    }
                        Item {
                            id: t3AnswerRow
                            readonly property var req: row.modelData.request
                            readonly property var st: req ? (ap.t3Answers[req.id] || null) : null
                            visible: row.modelData.src === "t3" && row.needs && !!req
                            width: parent.width
                            height: visible ? t3Btns.height + 6 + (t3Why.visible ? t3Why.implicitHeight + 4 : 0) : 0
                            Row {
                                id: t3Btns
                                y: 6
                                spacing: 8
                                enabled: !(t3AnswerRow.st && (t3AnswerRow.st.busy || t3AnswerRow.st.done))
                                opacity: enabled ? 1 : 0.6
                                Button {
                                    height: Theme.sp(30); size: Theme.tSub
                                    text: t3AnswerRow.st && t3AnswerRow.st.done === "decline" ? "Denied" : "Deny"
                                    onClicked: ap.answerT3(row.modelData, "decline")
                                    Accessible.name: "Deny " + row.modelData.title + ": " + row.modelData.question
                                }
                                Button {
                                    visible: !t3Allow.visible
                                    height: Theme.sp(30); size: Theme.tSub
                                    text: "Open in T3 Code"
                                    onClicked: ap.go(row.modelData)
                                }
                                Button {
                                    id: t3Allow
                                    readonly property string prompt: t3AnswerRow.req ? String(t3AnswerRow.req.prompt || "") : ""
                                    visible: prompt.trim() !== "" && prompt.length < 2000
                                    height: Theme.sp(30); size: Theme.tSub
                                    text: t3AnswerRow.st && t3AnswerRow.st.done === "accept" ? "Allowed" : "Allow"
                                    kind: "primary"
                                    onClicked: ap.answerT3(row.modelData, "accept")
                                    Accessible.name: "Allow " + row.modelData.title + ": " + row.modelData.question
                                }
                            }
                            Label {
                                id: t3Why
                                visible: !!t3AnswerRow.st && !t3AnswerRow.st.busy && t3AnswerRow.st.why !== ""
                                anchors { top: t3Btns.bottom; topMargin: 4 }
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: t3AnswerRow.st ? t3AnswerRow.st.why : ""
                                size: Theme.tFootnote; color: Theme.orange
                            }
                        }
                        // Answer it from here (Claude Code, Codex): kittymux types the
                        // key only if this exact question is still on screen. Deny
                        // first, Allow last; Enter on the row goes there, never Allow.
                        Item {
                            id: answerRow
                            readonly property var r: row.modelData.raw
                            readonly property var st: r ? (Kittymux.answers[r.key] || null) : null
                            visible: row.modelData.src === "kitty" && Kittymux.canAnswer(r)
                            width: parent.width
                            height: visible ? answerBtns.height + 6 + (answerWhy.visible ? answerWhy.implicitHeight + 4 : 0) : 0
                            HoverHandler { id: answerHover }
                            Row {
                                id: answerBtns
                                y: 6
                                spacing: 8
                                enabled: !(answerRow.st && answerRow.st.busy)
                                opacity: enabled ? 1 : 0.6
                                Button {
                                    height: Theme.sp(30); size: Theme.tSub
                                    text: answerRow.st && answerRow.st.done === "deny" ? "Denied" : "Deny"
                                    onClicked: Kittymux.answer(answerRow.r, "deny")
                                    Accessible.name: "Deny " + row.modelData.title + ": " + (Kittymux.askFor(answerRow.r) ? Kittymux.askFor(answerRow.r).what : row.modelData.question)
                                }
                                Button {
                                    height: Theme.sp(30); size: Theme.tSub
                                    text: answerRow.st && answerRow.st.done === "allow" ? "Allowed" : "Allow"
                                    kind: "primary"
                                    onClicked: Kittymux.answer(answerRow.r, "allow")
                                    Accessible.name: "Allow " + row.modelData.title + ": " + (Kittymux.askFor(answerRow.r) ? Kittymux.askFor(answerRow.r).what : row.modelData.question)
                                }
                            }
                            // Refused (the prompt changed, or it's gone): why, and the row still jumps there.
                            Label {
                                id: answerWhy
                                visible: !!answerRow.st && !answerRow.st.busy && answerRow.st.why !== ""
                                anchors { top: answerBtns.bottom; topMargin: 4 }
                                width: parent.width
                                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                text: answerRow.st ? answerRow.st.why + (answerRow.st.done ? "" : " · open it to answer") : ""
                                size: Theme.tFootnote; color: answerRow.st && answerRow.st.done ? Theme.textTertiary : Theme.orange
                            }
                        }
                }
                HoverHandler {
                    id: rowHover
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: {
                        if (hovered) { ap.keyboard = false; ap.sel = row.index; ap.hoverRow = row.plate; }
                        else if (ap.hoverRow === row.plate) ap.hoverRow = null;
                    }
                }
                TapHandler { onTapped: if (!xHover.hovered && !answerHover.hovered) ap.go(row.modelData) }
                Accessible.onPressAction: ap.go(row.modelData)
                Rectangle {
                    visible: row.dismissable
                    opacity: rowHover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
                    anchors { right: parent.right; rightMargin: 8; top: plate.top; topMargin: 8 }
                    width: 22; height: 22; radius: 11
                    color: xHover.hovered ? Theme.pillHover : Theme.pill
                    Behavior on color { ColorAnimation { duration: Theme.hoverMs } }
                    Text { anchors.centerIn: parent; text: "\u{f0156}"; font.family: Theme.fontGlyph; font.pixelSize: Theme.tSub; color: Theme.textSecondary }
                    HoverHandler { id: xHover; margin: 8 }
                    TapHandler { margin: 8; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: swipe.away(1) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Remove " + row.modelData.title
                    Accessible.onPressAction: swipe.away(1)
                }
            }
        }
        ScrollFade { flickable: list }
        ScrollHint { flickable: list; inside: true }

        Rectangle {
            id: portsCard
            visible: ap.ports.length > 0 && Settings.agentServers
            width: parent.width
            height: portsCol.implicitHeight + Theme.s2 * 2
            radius: Theme.r3
            color: Theme.card
            border.width: 1; border.color: Theme.cardEdge
            ListView {
                id: portsCol
                x: Theme.s3; y: Theme.s2
                width: parent.width - Theme.s3 * 2
                readonly property real rowH: Theme.sp(36)
                height: Math.min(count, 2) * rowH
                implicitHeight: height
                clip: true
                interactive: count > 2
                boundsBehavior: Flickable.StopAtBounds
                model: ap.ports
                delegate: Item {
                        required property var modelData
                        width: portsCol.width
                        height: portsCol.rowH
                        Row {
                            id: portWords
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - portOpen.width - Theme.s2
                            spacing: Theme.s2
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: Theme.green }
                            Label {
                                id: portNum
                                anchors.verticalCenter: parent.verticalCenter
                                text: ":" + modelData.port
                                size: Theme.tSub; weight: Theme.wBold
                                tabular: true
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, portWords.width - portNum.width - 6 - Theme.s2 * 2)
                                elide: Text.ElideRight
                                text: modelData.proc + " · " + modelData.project
                                size: Theme.tSub; color: Theme.textSecondary
                            }
                        }
                        Button {
                            id: portOpen
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            height: Theme.sp(28); size: Theme.tFootnote
                            text: "Open"
                            onClicked: { Apps.open("http://localhost:" + modelData.port); Island.close(); }
                            Accessible.name: "Open localhost port " + modelData.port + ", " + modelData.proc + " in " + modelData.project
                        }
                    }
            }
            ScrollHint { flickable: portsCol; inside: true }
        }


        // Opened from the keyboard: the keys, quietly (the pointer has the buttons).
        KeyHints {
            id: keyHints
            visible: Island.via === "key"
            hints: [["↑↓", "Choose"], ["↩", "Go"], ["⌫", "Mark read / forget"], ["A", "All read"], ["U", "Usage"], ["esc", "Back"]]
        }
        // The way on: how much they've got left, or the full list with recent ones to resume.
        Label {
            id: budgetNote
            visible: ap.budgetLine !== ""
            width: parent.width
            wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            text: ap.budgetLine + (ap.overBudget ? " · over" : "")
            size: Theme.tFootnote; color: ap.overBudget ? Theme.orange : Theme.textTertiary
            tabular: true
        }
        Item {
            id: health
            visible: Providers.troubleLine !== ""
            width: parent.width
            height: visible ? Math.max(Theme.sp(Theme.s5), healthLine.implicitHeight) : 0
            Rectangle {
                id: healthDot
                y: (Theme.sp(Theme.s5) - height) / 2
                width: 6; height: 6; radius: 3
                color: Theme.orange
            }
            Label {
                id: healthLine
                anchors { left: healthDot.right; leftMargin: Theme.s2; right: parent.right; verticalCenter: parent.verticalCenter }
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                text: Providers.troubleLine
                size: Theme.tFootnote; color: Theme.textSecondary
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Island.open("usage", Island.screen, "pointer") }
            Accessible.role: Accessible.Button
            Accessible.name: Providers.troubleLine + ". Open Usage"
            Accessible.onPressAction: Island.open("usage", Island.screen, "pointer")
        }
        Row {
            id: footRow
            width: parent.width
            spacing: 8
            Button {
                width: (parent.width - 8) / 2
                text: "Usage"
                onClicked: Island.open("usage", Island.screen, "pointer")
            }
            Button {
                width: (parent.width - 8) / 2
                enabled: (Kittymux.attention || []).length > 0
                text: (Kittymux.attention || []).length ? "Mark all read (" + Kittymux.attention.length + ")" : "All read"
                onClicked: Kittymux.ackAll()
            }
        }
    }
}
