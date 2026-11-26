pragma Singleton
// T3 Code's live work for the island: how many threads are running and how
// many wait for you (bin/kuwai-t3 reads T3's own state database read-only).
// Read when T3 writes: its database's write-ahead log and its
// server-runtime.json are watched (inotify; reading never triggers it), a
// window closing reads too (T3 quitting). The log changes ~100 times a
// second while agents work, so after a change the watch rests: kuwai-t3
// runs, again 5 s later while its answer keeps changing, and the watch comes
// back once two answers agree. Busy: one read per 5 s, as before. Quiet:
// nothing (it was every 5 s while T3 ran, every 30 s while it didn't).
// Nothing while locked or the screens are off; one read on the way back.
//
//   T3Code.running / waiting / items [{ status, title, provider }]
//   T3Code.focus()        bring the T3 Code window forward
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config
import "t3.mjs" as T3

Singleton {
    id: root
    property bool alive: false
    property real lastGoodAt: 0
    readonly property bool stale: !alive && lastGoodAt > 0 && rawItems.length > 0
    property int running: 0
    property int waiting: 0
    // Completed in the last 15 min and not dismissed here (shown in the panel,
    // the ✓ on the capsule).
    readonly property int finished: Math.max(0, rawFinished - rawItems.filter(i => (i.status === "completed" || i.status === "failed") && isDismissed(i)).length)
    property int rawFinished: 0
    property var rawItems: []
    // What T3 lists, minus the finished threads you swiped away or closed
    // with × (a finished thread you've dealt with, without opening it).
    readonly property var items: rawItems.filter(i => !isDismissed(i))
    readonly property var liveItems: alive ? items : []
    readonly property int liveFinished: alive ? finished : 0
    // Keyed by thread and when it finished, so the same thread finishing again
    // comes back. Kept across restarts, the 200 newest; nothing else is stored.
    property var dismissed: []
    function keyOf(i) { return String(i.thread) + "@" + String(i.at || ""); }
    function isDismissed(i) { return (i.status === "completed" || i.status === "failed") && dismissed.indexOf(keyOf(i)) >= 0; }
    function dismiss(i) {
        if (!i || dismissed.indexOf(keyOf(i)) >= 0) return;
        dismissed = dismissed.concat([keyOf(i)]).slice(-200);
        dismissedFile.setText(JSON.stringify(dismissed));
    }
    FileView {
        id: dismissedFile
        path: Paths.stateHome + "/kuwai/t3-dismissed.json"
        printErrors: false
        onLoaded: { try { const d = JSON.parse(text()); if (Array.isArray(d)) root.dismissed = d; } catch (e) {} }
    }
    property string env: ""              // T3 Code's environment id (its thread links need it)
    property string lastText: ""
    readonly property int total: running + waiting

    readonly property string bin: Paths.bin + "/kuwai-t3"
    readonly property string userdata: Quickshell.env("T3_USERDATA") || Quickshell.env("HOME") + "/.t3/userdata"
    readonly property bool away: Saver.locked || Saver.screensOff
    property bool settling: false        // the log changed: reading until two answers agree
    property bool lastChanged: false
    FileView {
        path: root.userdata + "/statev2.sqlite-wal"
        preload: false
        printErrors: false
        watchChanges: !root.settling && !root.away
        onFileChanged: root.changed()
    }
    FileView {
        path: root.userdata + "/server-runtime.json"
        preload: false
        printErrors: false
        watchChanges: true
        onFileChanged: root.changed()
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "closewindow" && root.alive) root.changed(); }
    }
    function changed() {
        if (away || settling) return;
        settling = true;
        read();
    }
    function read() { if (!poll.running) poll.running = true; }
    // Back from the lock or dark screens: what changed meanwhile wasn't
    // watched, so read once.
    onAwayChanged: if (!away) { settling = true; read(); }
    Timer {
        id: again
        interval: 5000
        onTriggered: {
            if (root.away) return;               // settling stays; read on the way back
            if (root.lastChanged) root.read();
            else root.settling = false;          // two answers agree: watch again
        }
    }
    Process {
        id: poll
        command: [root.bin]
        onExited: if (!again.running) again.restart()   // no output at all: still rest, then watch
        stdout: StdioCollector {
            onStreamFinished: {
                root.lastChanged = text !== root.lastText;
                again.restart();
                // Unchanged output: nothing to parse or compare.
                if (!root.lastChanged) return;
                root.lastText = text;
                try {
                    const d = JSON.parse(text);
                    if (d.error) { root.alive = true; return; }
                    const up = !!d.alive;
                    root.alive = up;
                    root.running = up ? (d.running || 0) : 0;
                    root.waiting = up ? (d.waiting || 0) : 0;
                    const next = d.items || [];
                    if (up) {
                        root.lastGoodAt = Date.now();
                        root.rawFinished = d.finished || 0;
                        root.env = d.env || "";
                        if (JSON.stringify(next) !== JSON.stringify(root.rawItems)) root.rawItems = next;
                    } else if (root.lastGoodAt === 0) {
                        root.rawFinished = 0;
                        root.env = "";
                        if (root.rawItems.length > 0) root.rawItems = [];
                    }
                } catch (e) {}
            }
        }
    }
    Component.onCompleted: { settling = true; read(); }

    // A thread's last reply, for the panel's preview: asked for one thread,
    // when its row is rested on (never in the background), and kept until that
    // thread moves on (its time changes). Plain lines, made by t3.mjs.
    property var replies: ({})                 // thread → { text, at, of }
    function wantReply(item) {
        if (!item || !item.thread) return;
        const had = replies[item.thread];
        if (had && had.of === item.at) return;
        if (replyReader.running) { replyReader.next = item; return; }
        replyReader.item = item;
        replyReader.command = [root.bin, "reply", String(item.thread)];
        replyReader.running = true;
    }
    Process {
        id: replyReader
        property var item: null
        property var next: null
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) {}
                const it = replyReader.item, kept = {};
                // Only threads still listed are kept: the cache can't outgrow the list.
                for (const i of root.rawItems) if (root.replies[i.thread]) kept[i.thread] = root.replies[i.thread];
                if (it) kept[it.thread] = { text: T3.excerpt(d.text), at: d.at || "", of: it.at };
                root.replies = kept;
                const n = replyReader.next;
                replyReader.item = null; replyReader.next = null;
                if (n) Qt.callLater(() => root.wantReply(n));
            }
        }
    }

    // One thread, in T3 Code: its own link (t3code://threads/ENV/THREAD; the
    // desktop app routes a second launch's link to that thread). Without the
    // ids it falls back to bringing the window forward.
    function openThread(thread) {
        if (!thread || !env) { focus(); return; }
        Apps.open("t3code://threads/" + encodeURIComponent(env) + "/" + encodeURIComponent(thread));
        focus();
    }
    // The thread that matters most: the one that needs you, else the newest
    // working or unseen-finished one (items come in that order). Nothing
    // listed: just the window.
    function openBest() {
        const it = items.find(i => i.thread);
        if (it) openThread(it.thread); else focus();
    }
    property var answers: ({})
    function setAnswer(id, v) { const n = Object.assign({}, answers); n[id] = v; answers = n; }
    function answer(thread, id, decision) {
        if (!thread || !id || (answers[id] || {}).busy) return;
        setAnswer(id, { busy: true, done: "", why: "" });
        answerProc.createObject(root, { asked: { id: id, decision: decision },
            command: [Paths.bin + "/kuwai-t3-answer", String(thread), String(id), decision] }).running = true;
    }
    Component {
        id: answerProc
        Process {
            id: one
            property var asked: null
            onExited: destroy(1000)
            stdout: StdioCollector {
                onStreamFinished: {
                    const p = one.asked;
                    let r = {};
                    try { r = JSON.parse(text); } catch (e) {}
                    root.setAnswer(p.id, { busy: false, done: r.ok ? p.decision : "",
                        why: r.ok ? "" : r.why === "scope" ? "T3's token for Kuwai can't answer yet (it needs orchestration:operate). Open it in T3."
                            : r.why === "gone" ? "Already answered." : "T3 didn't take it. Open it in T3." });
                    if (r.ok) root.read();
                }
            }
        }
    }
    // qs ipc -p <shell> call t3 best | open THREAD  (keybinds, tests)
    IpcHandler {
        target: "t3"
        function best(): void { root.openBest(); }
        function open(thread: string): void { root.openThread(thread); }
    }
    function focus() {
        // A Lua long string, as Notifs does: no quote/escape juggling.
        Hyprland.dispatch("hl.dsp.focus({window = [[class:^(com\\.t3tools\\.T3Code|t3code)$]]})");
    }
}
