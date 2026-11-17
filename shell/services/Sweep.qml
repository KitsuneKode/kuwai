pragma Singleton

// Idle projects, for the island: how much space sweep could give back, and
// which old projects hold it (the island's mark, SweepPanel, the launcher).
// The work is bin/rice-sweep's: it prints its last answer at once and, when
// that is older than 30 minutes, refreshes in the background at idle priority.
// So this only ever reads a cache (a few ms) and never waits on a scan.
//
//   Sweep.fresh        the mark shows: enabled, sweep found, the number is worth
//                      acting on (Settings.sweepMinGB) and new to you (looking
//                      keeps the size you saw; it returns 5 GB past that)
//   Sweep.compact      "16G", the mark's value
//   Sweep.openUi()     sweep's own review, in a terminal. Nothing is deleted
//                      from the island: removal stays behind sweep's confirm.
//
// Without sweep installed, `alive` is false and nothing here shows.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "sweepModel.js" as Model

Singleton {
    id: root

    readonly property string bin: Quickshell.shellDir + "/../bin/rice-sweep"
    readonly property bool enabled: Settings.sweepMark

    property var data: null
    readonly property bool alive: !!data && data.alive === true
    // First run: the first scan is still being made.
    readonly property bool pending: alive && data.pending === true
    readonly property real idleBytes: alive && data.idle ? data.idle.bytes || 0 : 0
    readonly property int idleProjects: alive && data.idle ? data.idle.projects || 0 : 0
    readonly property int idleDays: alive && data.idle ? data.idle.days || 30 : 30
    readonly property real reclaimable: alive ? data.reclaimable || 0 : 0
    readonly property int protectedCount: alive ? data.protected || 0 : 0
    readonly property var kinds: alive && data.kinds ? data.kinds : []
    readonly property var projects: alive && data.projects ? data.projects : []
    readonly property real checkedAt: alive && data.checkedAt ? data.checkedAt : 0
    readonly property string scanRoot: alive && data.root ? data.root : ""
    // An answer has come back (before it, the panel says it's looking).
    readonly property bool loaded: data !== null
    // A refresh is running behind the answer shown (first run, or stale).
    readonly property bool refreshing: alive && data.refreshing === true
    // The last refresh failed ("folder missing", "scan failed (exit 2)"); the
    // last good answer, if any, is still shown.
    readonly property string error: alive && data.error ? String(data.error) : ""

    readonly property real minBytes: Settings.sweepMinGB * 1e9
    readonly property bool worth: enabled && alive && !pending && Model.worthMark(idleBytes, minBytes)
    // The idle size you last looked at, in bytes (null: unseen). The mark
    // comes back once the number is 5 GB past it (sweepModel.isFresh).
    property var viewedBytes: null
    property bool viewedRead: false
    readonly property bool fresh: worth && viewedRead && Model.isFresh(idleBytes, viewedBytes, minBytes)
    readonly property string compact: Model.compact(idleBytes)
    readonly property string tip: Model.long(idleBytes) + " in " + idleProjects + (idleProjects === 1 ? " idle project" : " idle projects")
        + "\nRest on it for which · click to review in sweep"

    FileView {
        id: viewedFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rice/sweep-viewed"
        printErrors: false
        onLoaded: { root.viewedBytes = Model.parseViewed(text()); root.viewedRead = true; root.reconcile(); }
        onLoadFailed: root.viewedRead = true          // no file yet: unseen
    }
    function keepViewed(v) {
        if (v === viewedBytes) return;
        viewedBytes = v;
        viewedFile.setText(Model.viewedText(v));
    }
    // A real count moved the number: below the threshold the look is
    // forgotten; after a clean-up it follows the number down.
    readonly property bool counted: alive && !pending && checkedAt > 0
    function reconcile() {
        if (viewedRead && counted) keepViewed(Model.reconcileViewed(idleBytes, viewedBytes, minBytes));
    }
    onIdleBytesChanged: reconcile()
    onMinBytesChanged: reconcile()
    // You looked (the panel held for a moment, a click, a key, sweep opened).
    function markViewed() {
        if (viewedRead && counted) keepViewed(Model.viewedAfterLook(idleBytes, viewedBytes, minBytes));
    }

    property int retries: 0
    readonly property int maxRetries: 6
    // The mark's own beat runs only while it's enabled; `force` is someone
    // asking (the panel open, `rice sweep`, the IPC), which works with the
    // mark off too: the off switch is for the mark, not for the panel.
    function check(force) { if ((enabled || force) && !poll.running) poll.running = true; }
    Process {
        id: poll
        command: [root.bin]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (JSON.stringify(d) !== JSON.stringify(root.data)) root.data = d;
                    // A refresh runs behind this answer (first run, or a stale
                    // cache): look again soon, a few times, then settle to the
                    // beat. The count of tries is kept until it's done, so a slow
                    // scan gets one look per beat after the cap, not a new burst.
                    if (d.alive && (d.pending || d.refreshing)) {
                        if (root.retries < root.maxRetries) { root.retries++; again.restart(); }
                    } else root.retries = 0;
                } catch (e) {}
            }
        }
    }
    Timer { id: again; interval: 20000; onTriggered: root.check(true) }
    // Not at login (the first scan would compete with everything starting):
    // a little after, then every few minutes. Each call reads the cache.
    Timer { interval: 45000; running: root.enabled; onTriggered: root.check() }
    Timer { interval: 300000; running: root.enabled; repeat: true; onTriggered: root.check() }

    // sweep's review, in a terminal on the folder it counted. PATH gets the
    // places sweep is usually installed, which a desktop session often lacks.
    function openUi() {
        markViewed();
        const dir = scanRoot || Quickshell.env("HOME") + "/Projects";
        Quickshell.execDetached(["kitty", "--single-instance", "--instance-group=local", "--title", "sweep", "--directory", dir,
            "sh", "-c", "PATH=\"$HOME/.bun/bin:$HOME/.local/bin:$PATH\" exec sweep ui \"$1\"", "sh", dir]);
    }
    // qs ipc -p <shell> call sweep open | refresh  (keybinds, tests)
    IpcHandler {
        target: "sweep"
        function open(): void { root.openUi(); }
        function refresh(): void { root.check(true); }
    }
}
