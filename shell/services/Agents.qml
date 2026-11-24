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

    readonly property string desktopPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/kuwai/desktop-agents.json"
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

    readonly property var desktop: desktopFeed.filter(d => d && d.id && (!d.updated_at || !d.ttl || root.now / 1000 - d.updated_at <= d.ttl))

    readonly property var panes: {
        const events = Kittymux.attention || [];
        return Kittymux.running.map(r => {
            const ev = events.find(e => e.severity === "needs-you" && String(e.pid) === String(r.pid) && String(e.w) === r.w);
            return {
                key: r.key, agent: r.agent, title: r.title, account: r.account || "",
                state: ev && r.state !== "error" && r.state !== "limited" ? "waiting" : r.state || (r.working ? "working" : ""),
                needs: r.needs || !!ev, working: r.working, ask: !!Kittymux.askFor(r),
                since: r.since || 0, limitReset: r.limitReset || 0, event: ev ? ev.id : "", action: r.action
            };
        });
    }
    readonly property int doneKitty: (Kittymux.attention || []).filter(e => e.kind === "done").length
    readonly property int doneDesktop: desktop.filter(d => d.state === "done").length
    readonly property var head: A.headline(panes, T3Code.items, doneKitty, T3Code.finished, now, desktop, doneDesktop)
    readonly property var next: A.target(panes, T3Code.items, desktop)
    readonly property var extraLimited: A.limitedItems(panes, T3Code.items, desktop).map(it => ({
        key: it.key,
        id: it.agent,
        brand: Kittymux.brand(it.agent),
        tint: String(Theme.brandTint[it.agent] || Theme.yellow),
        name: Kittymux.agentLabel(it.agent),
        account: it.account || "",
        resetsAt: it.reset || 0,
        windowLabel: "Limit",
        source: it.src
    }))

    function t3Agent(p) { return A.t3Agent(p); }
    function stateGlyph(key) { return A.stateGlyph(key); }

    function focusDesktop(it) {
        const cls = String((it && (it.windowClass || it.window_class)) || "");
        if (!cls || cls.indexOf("]]") >= 0) return false;
        Hyprland.dispatch("hl.dsp.focus({window = [[class:" + cls + "]]})");
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
                desktop: root.desktop.length,
                next: root.next ? { src: root.next.src, word: root.next.word, title: root.next.title } : null
            });
        }
    }
}
