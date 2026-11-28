pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "sweepModel.js" as Model
import "sizes.mjs" as Sizes

Singleton {
    id: root

    readonly property string bin: Paths.bin + "/kuwai-sweep"
    readonly property string stateDir: Paths.stateHome + "/kuwai"
    readonly property bool enabled: Settings.sweepMark

    property var data: null
    readonly property bool alive: !!data && data.alive === true
    readonly property bool pending: alive && data.pending === true
    readonly property real idleBytes: alive && data.idle ? data.idle.bytes || 0 : 0
    readonly property int idleProjects: alive && data.idle ? data.idle.projects || 0 : 0
    readonly property int idleDays: alive && data.idle ? data.idle.days || 30 : 30
    readonly property real reclaimable: alive ? data.reclaimable || 0 : 0
    readonly property int protectedCount: alive ? data.protected || 0 : 0
    readonly property var kinds: alive && data.kinds ? data.kinds : []
    readonly property var idleKinds: alive && data.idle && Array.isArray(data.idle.kinds) ? data.idle.kinds : []
    readonly property var projects: alive && data.projects ? data.projects : []
    readonly property real checkedAt: alive && data.checkedAt ? data.checkedAt : 0
    readonly property string scanRoot: alive && data.root ? data.root : ""
    readonly property bool loaded: data !== null
    readonly property bool refreshing: alive && data.refreshing === true
    readonly property string error: alive && data.error ? String(data.error) : ""

    readonly property real minBytes: Settings.sweepMinGB * Sizes.GB
    readonly property bool worth: enabled && alive && !pending && Model.worthMark(idleBytes, minBytes)
    property var viewedBytes: null
    property bool viewedRead: false
    readonly property bool fresh: worth && viewedRead && Model.isFresh(idleBytes, viewedBytes, minBytes)
    readonly property string compact: Model.compact(idleBytes)
    readonly property string tip: Model.long(idleBytes) + " in " + idleProjects + (idleProjects === 1 ? " idle project" : " idle projects")
        + "\nRest on it or click for which · review them in sweep from there"

    FileView {
        id: viewedFile
        path: root.stateDir + "/sweep-viewed"
        printErrors: false
        onLoaded: { root.viewedBytes = Model.parseViewed(text()); root.viewedRead = true; root.reconcile(); }
        onLoadFailed: root.viewedRead = true
    }
    function keepViewed(v) {
        if (v === viewedBytes) return;
        viewedBytes = v;
        viewedFile.setText(Model.viewedText(v));
    }
    readonly property bool counted: alive && !pending && checkedAt > 0
    function reconcile() {
        if (viewedRead && counted) keepViewed(Model.reconcileViewed(idleBytes, viewedBytes, minBytes));
    }
    onIdleBytesChanged: reconcile()
    onMinBytesChanged: reconcile()
    function markViewed() {
        if (viewedRead && counted) keepViewed(Model.viewedAfterLook(idleBytes, viewedBytes, minBytes));
    }

    property int retries: 0
    readonly property int maxRetries: 6
    property int askAge: 0
    property int queuedAge: -1
    function check(force, maxAge) {
        if (!enabled && !force) return;
        if (poll.running) { queuedAge = Math.max(queuedAge, maxAge || 0); return; }
        askAge = maxAge || 0;
        poll.running = true;
    }
    Process {
        id: poll
        command: root.askAge > 0 ? [root.bin, "--max-age", String(root.askAge)] : [root.bin]
        onExited: if (root.queuedAge >= 0) { const a = root.queuedAge; root.queuedAge = -1; root.check(true, a); }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (JSON.stringify(d) !== JSON.stringify(root.data)) root.data = d;
                    if (d.alive && (d.pending || d.refreshing)) {
                        if (root.retries < root.maxRetries) { root.retries++; again.restart(); }
                    } else root.retries = 0;
                } catch (e) {}
            }
        }
    }
    Timer { id: again; interval: 20000; onTriggered: root.check(true) }
    Timer { interval: 45000; running: root.enabled; onTriggered: root.check() }
    Timer { interval: 300000; running: root.enabled; repeat: true; onTriggered: root.check() }
    FileView {
        path: root.stateDir + "/sweep-status.json"
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); cacheMoved.restart(); }
    }
    Timer { id: cacheMoved; interval: 250; onTriggered: if (root.data !== null) root.check(true) }

    function openUi(path) {
        markViewed();
        const dir = path || scanRoot || Quickshell.env("HOME") + "/Projects";
        Quickshell.execDetached([bin, "--open", dir]);
    }
    IpcHandler {
        target: "sweep"
        function open(): void { root.openUi(); }
        function refresh(): void { root.check(true); }
    }
}
