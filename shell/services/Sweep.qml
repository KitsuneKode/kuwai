pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.config
import "sweepModel.js" as Model
import "sizes.mjs" as Sizes
import "jobs.mjs" as Jobs
import "links.mjs" as Links
import "panelSchema.mjs" as Schema
import "sweepContract.mjs" as Contract

Singleton {
    id: root

    readonly property string bin: Paths.bin + "/kuwai-sweep"
    readonly property string stateDir: Paths.stateHome + "/kuwai"
    readonly property string home: (Quickshell.env("HOME") || "").replace(/\/+$/, "")
    readonly property string cacheHome: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache").replace(/\/+$/, "")
    readonly property string runtimeDir: Paths.runtime + "/sweep"
    readonly property string configuredRoot: (Quickshell.env("KUWAI_SWEEP_ROOT") || home + "/Projects").replace(/\/+$/, "")
    readonly property bool enabled: Settings.sweepMark

    property var data: null
    property var installed: null
    property string exe: ""
    property var upstream: null
    property bool scanning: false
    property bool shown: false
    property bool deliberate: false
    property bool manualNext: false
    property bool staleAfterReview: false
    property bool runtimeReady: false
    property var applyRaw: null
    property var receiptRaw: null
    property string dismissedId: ""
    property string bootId: ""
    property bool copied: false
    property bool onBattery: UPower.onBattery
    property bool applyFromFile: false
    property bool receiptFromFile: false
    property real now: Date.now()

    readonly property var summary: Contract.summarize(data, configuredRoot)
    readonly property bool loaded: data !== null
    readonly property bool alive: summary.installed === true || (summary.installed !== false && installed === true)
    readonly property bool counted: alive && Contract.counted(summary)
    readonly property real idleBytes: counted ? summary.idleBytes : 0
    readonly property int idleProjects: counted ? summary.idleProjects : 0
    readonly property string scanRoot: summary.root || configuredRoot
    readonly property var apply: Contract.activeApply(applyRaw, now, bootId)
    readonly property var receipt: Contract.receipt(receiptRaw, now, dismissedId)
    readonly property string panelJson: JSON.stringify(Contract.toPanel(summary, {
        nowMs: now, onBattery: onBattery, scanning: scanning, installed: installed, apply: apply,
        receipt: receipt, copied: copied, reviewing: reviewing, markOff: !Settings.sweepMark }))
    readonly property var panel: JSON.parse(panelJson)

    readonly property real minBytes: Settings.sweepMinGB * Sizes.GB
    readonly property bool worth: enabled && counted && Model.worthMark(idleBytes, minBytes)
    property var viewedBytes: null
    property bool viewedRead: false
    readonly property bool fresh: worth && viewedRead && Model.isFresh(idleBytes, viewedBytes, minBytes)
    readonly property string compact: Model.compact(idleBytes)
    readonly property string tip: Model.long(idleBytes) + " in " + idleProjects + (idleProjects === 1 ? " idle project" : " idle projects")
        + "\nRest on it or click for which · review them in Sweep from there"

    function json(text) {
        const t = String(text || "");
        if (t.length === 0 || t.length > 4 * Schema.MAX_BYTES) return null;
        try { return JSON.parse(t); } catch (e) { return null; }
    }
    function take(source, text) {
        const o = json(text);
        if (!o || typeof o !== "object") return;
        if (source === "widget") {
            const snap = Contract.snapshotOf(o, configuredRoot);
            if (snap && upstream !== false) data = snap;
        } else if (upstream !== true && !(data && data.widgetSchemaVersion !== undefined)) {
            data = o;
        }
    }

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
    function reconcile() {
        if (viewedRead && counted) keepViewed(Model.reconcileViewed(idleBytes, viewedBytes, minBytes));
    }
    onIdleBytesChanged: reconcile()
    onMinBytesChanged: reconcile()
    function markViewed() {
        if (viewedRead && counted) keepViewed(Model.viewedAfterLook(idleBytes, viewedBytes, minBytes));
    }

    FileView {
        id: legacyFile
        path: root.stateDir + "/sweep-status.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.take("legacy", text())
    }
    FileView {
        id: widgetFile
        path: root.cacheHome + "/sweep/widget-v1.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.take("widget", text())
    }
    FileView {
        id: applyFile
        path: root.runtimeReady ? root.runtimeDir + "/active-apply.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { root.applyRaw = root.json(text()); root.applyFromFile = true; root.now = Date.now(); }
        onLoadFailed: if (root.applyFromFile) { root.applyRaw = null; root.applyFromFile = false; }
    }
    FileView {
        id: receiptFile
        path: Paths.stateHome + "/sweep/last-receipt.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { root.receiptRaw = root.json(text()); root.receiptFromFile = true; }
        onLoadFailed: if (root.receiptFromFile) { root.receiptRaw = null; root.receiptFromFile = false; }
    }
    FileView {
        id: dismissedFile
        path: root.stateDir + "/sweep-state.json"
        printErrors: false
        onLoaded: root.dismissedId = Contract.parseDismissed(text())
    }
    FileView {
        path: "/proc/sys/kernel/random/boot_id"
        printErrors: false
        onLoaded: root.bootId = text().trim()
    }
    Process {
        id: makeRuntime
        command: ["mkdir", "-p", "-m", "0700", "--", root.runtimeDir]
        onExited: root.runtimeReady = true
    }
    function dismissReceipt() {
        if (!receipt) return;
        dismissedId = receipt.id;
        dismissedFile.setText(Contract.dismissedText(receipt.id));
    }

    function opened(deliberateOpen) {
        shown = true;
        now = Date.now();
        if (deliberateOpen) deliberate = true;
        legacyFile.reload();
        widgetFile.reload();
        receiptFile.reload();
        if (applyFile.path !== "") applyFile.reload();
        if (!probe.running) probe.running = true;
        watchReview();
    }
    function closed() {
        if (receipt && deliberate) dismissReceipt();
        shown = false;
        deliberate = false;
        if (widget.running && !widget.cacheOnly) { widget.running = false; scanning = false; }
    }
    function refresh() {
        dismissReceipt();
        manualNext = true;
        if (!probe.running) probe.running = true;
    }
    function check(force) { if (force) refresh(); }
    Timer {
        interval: 10000
        repeat: true
        running: root.shown
        onTriggered: root.now = Date.now()
    }

    Process {
        id: probe
        command: Contract.probeArgv(root.home)
        stdout: StdioCollector {
            onStreamFinished: {
                root.exe = Contract.probed(text, root.home);
                root.installed = root.exe !== "";
                root.afterProbe();
            }
        }
    }
    function afterProbe() {
        if (installed && upstream === null) {
            if (widget.running) return;
            widget.cacheOnly = true;
            widget.command = Contract.widgetArgv(exe, configuredRoot, true);
            widget.running = true;
            return;
        }
        const manual = manualNext;
        manualNext = false;
        const p = Contract.plan({ band: staleAfterReview ? "stale" : Contract.band(summary.checkedAt, now), onBattery: onBattery,
            deliberate: deliberate && shown, manual: manual, scanning: scanning || summary.refreshing, installed: installed });
        if (p === "scan") scan(manual);
    }
    function scan(manual) {
        staleAfterReview = false;
        if (upstream === true && exe !== "") {
            if (widget.running) return;
            widget.cacheOnly = false;
            widget.command = Contract.widgetArgv(exe, configuredRoot, false);
            scanning = true;
            widget.running = true;
        } else if (!legacy.running) {
            legacy.command = [bin, "--max-age", manual ? "0" : String(Contract.QUIET_MS / 1000)];
            legacy.running = true;
        }
    }
    Process {
        id: widget
        property bool cacheOnly: true
        stdout: StdioCollector {
            onStreamFinished: {
                const o = root.json(text);
                const snap = o ? Contract.snapshotOf(o, root.configuredRoot) : null;
                if (widget.cacheOnly) {
                    root.upstream = !!snap;
                    if (snap && snap.projectsSummary) root.data = snap;
                    root.afterProbe();
                } else {
                    if (snap) root.data = snap;
                    root.scanning = false;
                }
            }
        }
        onExited: if (!cacheOnly) root.scanning = false
    }
    Process {
        id: legacy
        stdout: StdioCollector {
            onStreamFinished: {
                const o = root.json(text);
                if (o && root.upstream !== true && JSON.stringify(o) !== JSON.stringify(root.data)) root.data = o;
            }
        }
    }

    Process {
        id: copier
        command: ["wl-copy", "--", Contract.INSTALL_COMMAND]
        onExited: code => { root.copied = code === 0; if (root.copied) copiedFor.restart(); }
    }
    Timer { id: copiedFor; interval: 4000; onTriggered: root.copied = false }

    function act(intent, rowId, url) {
        const it = Schema.intentOf(intent, url);
        if (!it) return false;
        if (it.intent === "refresh") { refresh(); return false; }
        if (it.intent === "copyInstall") { if (!copier.running) { copied = false; copier.running = true; } return false; }
        if (it.intent === "openSettings") { Qt.callLater(() => Island.open("settings", Island.screen, "key")); return false; }
        if (it.intent === "openHelp") { Apps.open(Contract.HELP_URL); return true; }
        if (it.intent === "openUrl") { if (Links.safeLink(it.url)) Apps.open(it.url); return true; }
        dismissReceipt();
        openUi(Contract.reviewDir(summary, rowId, home));
        return true;
    }

    property var review: null
    property bool opening: false
    readonly property bool reviewing: opening || Jobs.running(review)
    function watchReview() { if (!reviewProbe.running) reviewProbe.running = true; }
    function openUi(path) {
        markViewed();
        if (reviewing) return;
        const dir = path || scanRoot;
        if (!dir) return;
        opening = true;
        const cmd = exe !== "" ? Contract.reviewArgv(Paths.bin + "/kuwai-term", exe, dir) : [bin, "--open", dir, "--wait"];
        reviewStart.command = [Paths.bin + "/kuwai-job", "start", "sweep", "review", "--"].concat(cmd);
        reviewStart.running = true;
    }
    Component.onCompleted: { makeRuntime.running = true; watchReview(); }
    Process {
        id: reviewStart
        stdout: StdioCollector {
            onStreamFinished: { root.opening = false; root.watchReview(); }
        }
    }
    FileView {
        path: root.stateDir + "/jobs/sweep.json"
        watchChanges: true
        printErrors: false
        onFileChanged: root.watchReview()
    }
    Process {
        id: reviewProbe
        command: [Paths.bin + "/kuwai-job", "status", "sweep"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.review = Jobs.parse(text);
                if (Jobs.running(root.review) || !Jobs.unseen(root.review)) return;
                reviewAck.running = true;
                root.staleAfterReview = true;
            }
        }
    }
    Process { id: reviewAck; command: [Paths.bin + "/kuwai-job", "ack", "sweep"] }
    IpcHandler {
        target: "sweep"
        function open(): void { root.openUi(""); }
        function refresh(): void { root.refresh(); }
    }
}
