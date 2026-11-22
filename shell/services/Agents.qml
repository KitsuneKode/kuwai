pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "agents.mjs" as A

Singleton {
    id: root

    property real now: Date.now()
    Timer {
        interval: 60000; repeat: true
        running: root.panes.some(p => p.state === "limited")
        onTriggered: root.now = Date.now()
    }

    readonly property var panes: {
        const events = Kittymux.attention || [];
        return Kittymux.running.map(r => {
            const ev = events.find(e => e.severity === "needs-you" && String(e.pid) === String(r.pid) && String(e.w) === r.w);
            return {
                key: r.key, agent: r.agent, title: r.title,
                state: ev && r.state !== "error" && r.state !== "limited" ? "waiting" : r.state || (r.working ? "working" : ""),
                needs: r.needs || !!ev, working: r.working, ask: !!Kittymux.askFor(r),
                since: r.since || 0, limitReset: r.limitReset || 0, event: ev ? ev.id : "", action: r.action
            };
        });
    }
    readonly property int doneKitty: (Kittymux.attention || []).filter(e => e.kind === "done").length
    readonly property var head: A.headline(panes, T3Code.items, doneKitty, T3Code.finished, now)
    readonly property var next: A.target(panes, T3Code.items)

    function t3Agent(p) { return A.t3Agent(p); }

    function go(it) {
        if (!it) return false;
        if (it.src === "t3") T3Code.openThread(it.thread);
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
        function state(): string { return JSON.stringify({ head: root.head, next: root.next ? { src: root.next.src, word: root.next.word, title: root.next.title } : null }); }
    }
}
