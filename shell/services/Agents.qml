pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config
import "agents.mjs" as A

Singleton {
    id: root

    property real now: Date.now()
    Timer {
        interval: 60000; repeat: true
        running: root.panes.some(p => p.state === "limited") || root.desktopFeed.length > 0
        onTriggered: root.now = Date.now()
    }

    readonly property string desktopPath: Paths.stateHome + "/kuwai/desktop-agents.json"
    readonly property string hookBin: Paths.bin + "/kuwai-agent-hook"
    property bool desktopPinned: false
    property var desktopFeed: []
    property bool desktopReady: false
    Process {
        id: desktopInit
        command: [root.hookBin, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.desktopPinned) {
                    try {
                        const d = JSON.parse(text);
                        if (Array.isArray(d)) root.desktopFeed = d;
                    } catch (e) {}
                }
                root.desktopReady = true;
            }
        }
    }
    FileView {
        id: desktopFile
        path: root.desktopReady ? root.desktopPath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (root.desktopPinned) return;
            try {
                const d = JSON.parse(text());
                if (d && Array.isArray(d.agents)) root.desktopFeed = d.agents;
                else if (Array.isArray(d)) root.desktopFeed = d;
            } catch (e) {}
        }
    }
    Component.onCompleted: desktopInit.running = true
    Timer {
        interval: 20000; repeat: true
        running: !root.desktopPinned && root.desktopFeed.some(d => d && ["working", "waiting", "needs"].includes(d.state))
        onTriggered: if (!desktopInit.running) desktopInit.running = true
    }

    readonly property var hooks: desktopFeed.filter(d => d && d.id && d.state && d.state !== "ready" && (!d.updated_at || !d.ttl || root.now / 1000 - d.updated_at <= d.ttl))

    readonly property var panes: {
        const events = Kittymux.attention || [];
        return Kittymux.running.map(r => {
            const ev = events.find(e => e.severity === "needs-you" && String(e.pid) === String(r.pid) && String(e.w) === r.w);
            return {
                key: r.key, agent: r.agent, title: r.title, account: r.account || "",
                state: ev && r.state !== "error" && r.state !== "limited" ? "waiting" : r.state || (r.working ? "working" : ""),
                needs: r.needs || !!ev, working: r.working, ask: !!Kittymux.askFor(r),
                since: r.since || 0, limitReset: r.limitReset || 0, event: ev ? ev.id : "", action: r.action,
                pid: r.pid || "", w: r.w || "", where: r.where || "", question: r.question || "", raw: r
            };
        });
    }
    readonly property var sessions: A.sessions(panes, T3Code.liveItems, hooks, { home: Quickshell.env("HOME") || "" })
    readonly property var desktop: sessions.filter(s => s.src === "desktop").map(s => s.hook)
    readonly property var tally: A.counts(sessions)
    property real lookedAt: 0
    property string lookedOn: ""
    function look() {
        lookedAt = Date.now();
        lookedFile.setText(JSON.stringify({ at: lookedAt }));
    }
    FileView {
        id: lookedFile
        path: Paths.stateHome + "/kuwai/agents-looked.json"
        printErrors: false
        onLoaded: { try { const d = JSON.parse(text()); if (d && d.at > root.lookedAt) root.lookedAt = d.at; } catch (e) {} }
    }
    Connections {
        target: Island
        function onPanelChanged() {
            if (Island.panel === "agents" || root.lookedOn === "agents") root.look();
            root.lookedOn = Island.panel;
        }
    }
    readonly property var t3DoneTimes: T3Code.alive ? T3Code.items.filter(i => i.status === "completed" || i.status === "failed").map(i => Date.parse(i.at) || 0) : []
    readonly property int doneT3: {
        const extra = Math.max(0, T3Code.liveFinished - t3DoneTimes.length);
        const oldest = Math.min(...t3DoneTimes.filter(t => t > 0), Infinity);
        return A.doneSince(t3DoneTimes, lookedAt) + (lookedAt < oldest ? extra : 0);
    }
    readonly property int doneKitty: A.doneSince((Kittymux.attention || []).filter(e => e.kind === "done").map(e => e.t || 0), lookedAt)
    readonly property int doneDesktop: A.doneSince(sessions.filter(s => s.src === "desktop" && s.state === "done").map(s => s.t || 0), lookedAt)
    readonly property var head: A.headlineOf(sessions, doneKitty, doneT3, doneDesktop)
    readonly property var next: A.targetOf(sessions)
    readonly property var items: A.ranked(sessions)
    readonly property int needN: tally.needs
    readonly property int workN: tally.working
    function stack(only) { return A.stackList(sessions, only); }
    function providerId(name) { return A.providerId(name); }
    readonly property var extraLimited: A.limitedOf(sessions).map(it => ({
        key: it.key,
        id: A.providerId(it.agent),
        brand: Kittymux.brand(it.agent),
        tint: String(Theme.brandTint[it.agent] || Theme.red),
        name: Kittymux.agentLabel(it.agent),
        account: it.account || "",
        resetsAt: it.reset || 0,
        windowLabel: "Limit",
        source: it.src
    }))

    function t3Agent(p) { return A.t3Agent(p); }
    function stackMarks(list, max) { return A.stackMarks(list, max); }
    function stateGlyph(key) { return A.stateGlyph(key); }

    function focusDesktop(it) {
        const raw = String((it && (it.windowClass || it.window_class)) || "");
        const names = raw.replace(/^\^\(?/, "").replace(/\)?\$$/, "").replace(/\\/g, "").split("|").filter(n => n);
        if (!names.length || !names.every(n => /^[A-Za-z0-9._:@+-]+$/.test(n))) return false;
        Hyprland.dispatch("hl.dsp.focus({window = [[class:^(" + names.map(n => n.replace(/\./g, "\\.")).join("|") + ")$]]})");
        return true;
    }

    function dismissDesktop(id) {
        if (!id) return;
        if (desktopPinned) {
            desktopFeed = desktopFeed.filter(d => d.id !== id);
            return;
        }
        dismissProc.createObject(root, { command: [root.hookBin, "dismiss", String(id)] }).running = true;
    }
    Component {
        id: dismissProc
        Process { onExited: destroy() }
    }

    function go(it) {
        if (!it) return false;
        if (it.src === "t3") T3Code.openThread(it.thread);
        else if (it.src === "desktop") return focusDesktop(it);
        else if (it.event) Kittymux.jumpEvent(it.event);
        else if (it.action) Kittymux.act(it.action);
        else return false;
        return true;
    }

    function goNeeds() {
        if (Island.panel !== "") Island.close();
        if (!go(next)) Island.open("agents", "", "key");
    }

    IpcHandler {
        target: "agents"
        function go(): void { root.goNeeds(); }
        function state(): string {
            return JSON.stringify({
                head: root.head,
                tally: root.tally,
                desktop: root.desktop.length,
                next: root.next ? { src: root.next.src, word: root.next.word, title: root.next.title } : null
            });
        }
    }
}
