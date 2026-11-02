pragma Singleton

// System updates: the one place that knows about them (the island's Updates
// panel, the alert, the System panel's row and the live activity all read
// this). The work is bin/rice-update's; this keeps its answers and runs it.
//
//   Arch packages   one group, updated together (Arch doesn't do partial
//                   upgrades): include or leave out, never pick and choose
//   AUR packages    each one shows what changed in its build files since the
//                   version you have; it can be selected only once you've
//                   approved that exact change (or you trust the package).
//                   Nothing is skipped silently.
//
// Checks: 2 minutes after login, then every 3 hours, and when the panel opens
// on a check older than 20 minutes. A check never needs root (checkupdates
// uses its own copy of the databases).

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    readonly property string bin: Paths.bin + "/rice-update"

    // ── What's pending ───────────────────────────────────────────────────
    property var data: null
    property bool checking: false
    property string checkError: ""
    readonly property var repo: data && data.repo ? data.repo : []
    readonly property var aur: data && data.aur ? data.aur : []
    readonly property var news: data && data.news ? data.news : []
    readonly property var flatpak: data && data.flatpak && Settings.updatesFlatpak ? data.flatpak : []
    readonly property var manualNews: news.filter(n => n.manual)
    readonly property int total: data ? repo.length + aur.length + flatpak.length : -1
    readonly property real checkedAt: data ? data.checkedAt * 1000 : 0

    function check() {
        if (checking || running) return;
        checking = true;
        checkError = "";
        checker.running = true;
    }
    function checkIfStale() { if (Date.now() - checkedAt > 20 * 60 * 1000) check(); }
    Process {
        id: checker
        command: [root.bin, "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.checking = false;
                try {
                    const d = JSON.parse(text);
                    if (d.error) { root.checkError = d.error; return; }
                    root.data = d;
                    // Approvals written by an earlier session still count.
                    const a = Object.assign({}, root.approvedSha);
                    for (const p of d.aur) if (p.approved) a[p.name] = p.approved;
                    root.approvedSha = a;
                    root.trusted = d.aur.filter(p => p.trusted).map(p => p.name).concat(root.trusted.filter(n => !d.aur.some(p => p.name === n)));
                } catch (e) { root.checkError = "Couldn't read the update check"; }
            }
        }
    }
    // The last answer, at once on start (the check itself takes seconds).
    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/rice/updates.json"
        printErrors: false
        onLoaded: { if (!root.data) { try { root.data = JSON.parse(text()); } catch (e) {} } }
    }
    Timer { interval: 120 * 1000; running: true; onTriggered: root.check() }
    Timer { interval: Math.max(1, Settings.updatesCheckHours) * 3600 * 1000; running: Settings.updatesCheckHours > 0; repeat: true; onTriggered: root.check() }

    // ── AUR review ───────────────────────────────────────────────────────
    property var reviews: ({})          // name → rice-update review JSON
    property string reviewing: ""
    property var approvedSha: ({})      // name → the commit you approved
    property var trusted: []
    property var excluded: ({})         // name → true: you switched it off for this run
    property bool includeRepo: true
    property var autoApproved: []       // approved by the setting (shown as such)
    property var flatpakOff: ({})       // Flatpak apps switched off for this run
    function setFlatpakOff(id, off) { const e = Object.assign({}, flatpakOff); if (off) e[id] = true; else delete e[id]; flatpakOff = e; }
    // Review in the background as soon as a check finds AUR changes, so the
    // panel (and the auto-approve setting) has answers before you open it.
    onDataChanged: { for (const p of aur) if (aurState(p.name) === "review") review(p.name); }

    function reviewOf(name) { return reviews[name] || null; }
    // Your saved approvals and trusted packages, at once on start (the
    // cached check can predate them).
    Process {
        running: true
        command: [root.bin, "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const st = JSON.parse(text);
                    root.trusted = st.trusted || [];
                    root.approvedSha = Object.assign({}, st.approved || {}, root.approvedSha);
                } catch (e) {}
            }
        }
    }
    // "trusted" · "approved" · "routine" (looked at: only versions changed) · "review" · "loading"
    function aurState(name) {
        if (trusted.indexOf(name) >= 0) return "trusted";
        const r = reviews[name];
        if (r && approvedSha[name] && approvedSha[name] === r.head) return "approved";
        if (!r && approvedSha[name]) return "approved";      // approved earlier; rice-update re-checks the commit
        if (reviewing === name) return "loading";
        return "review";
    }
    function selectable(name) { const s = aurState(name); return s === "trusted" || s === "approved"; }
    function selected(name) { return selectable(name) && !excluded[name]; }
    function setExcluded(name, off) { const e = Object.assign({}, excluded); if (off) e[name] = true; else delete e[name]; excluded = e; }

    property var reviewQueue: []
    function review(name) {
        if (reviews[name] || reviewing === name || reviewQueue.indexOf(name) >= 0) return;
        reviewQueue = [...reviewQueue, name];
        nextReview();
    }
    function nextReview() {
        if (reviewing || !reviewQueue.length) return;
        reviewing = reviewQueue[0];
        reviewQueue = reviewQueue.slice(1);
        reviewer.command = [bin, "review", reviewing];
        reviewer.running = true;
    }
    Process {
        id: reviewer
        stdout: StdioCollector {
            onStreamFinished: {
                const name = root.reviewing;
                const r = Object.assign({}, root.reviews);
                try { r[name] = JSON.parse(text); } catch (e) { r[name] = { error: "Couldn't read the review" }; }
                root.reviews = r;
                // Settings → Updates: a change that only moves versions and
                // checksums (nothing flagged, not new to you) is approved as read.
                const rv = r[name];
                if (Settings.updatesAutoRoutine && rv && !rv.error && rv.routine && !rv.firstTime && !(rv.flags && rv.flags.length) && rv.head) {
                    root.approve(name);
                    root.autoApproved = [...root.autoApproved.filter(n => n !== name), name];
                }
                root.reviewing = "";
                root.nextReview();
            }
        }
    }
    function approve(name) {
        const r = reviews[name];
        if (!r || !r.head) return;
        Quickshell.execDetached([bin, "approve", name, r.head]);
        const a = Object.assign({}, approvedSha); a[name] = r.head; approvedSha = a;
        setExcluded(name, false);
    }
    function unapprove(name) {
        const a = Object.assign({}, approvedSha); delete a[name]; approvedSha = a;
    }
    function setTrusted(name, on) {
        Quickshell.execDetached([bin, "trust", name, on ? "on" : "off"]);
        trusted = on ? [...trusted.filter(n => n !== name), name] : trusted.filter(n => n !== name);
    }

    // ── The run ──────────────────────────────────────────────────────────
    readonly property var chosenAur: aur.filter(p => selected(p.name)).map(p => p.name)
    readonly property var chosenFlatpak: flatpak.filter(p => !flatpakOff[p.id]).map(p => p.id)
    readonly property int chosenCount: (includeRepo ? repo.length : 0) + chosenAur.length + chosenFlatpak.length
    readonly property int waitingReview: aur.filter(p => !selectable(p.name)).length
    readonly property bool lowPower: !!(data && data.power && !data.power.ac && data.power.battery !== null && data.power.battery < 30)
    readonly property bool lowSpace: !!(data && data.freeBytes < 3 * 1024 * 1024 * 1024)

    property bool running: false
    property string phase: ""           // check · repo · build · install · after
    property string phaseLabel: ""
    property var phasesSeen: []
    property real progress: 0           // 0–1 within the run, for the island's ring
    property string currentLine: ""
    property var log: []
    property var result: null
    property string runError: ""
    property var plan: ({ repo: false, aur: [], flatpak: [] })

    function run() {
        if (running || chosenCount === 0 || lowSpace) return;
        plan = { repo: includeRepo && repo.length > 0, aur: chosenAur.slice(), flatpak: chosenFlatpak.slice() };
        const args = [bin, "start"];
        if (plan.repo) args.push("--repo");
        if (plan.aur.length) args.push("--aur", ...plan.aur);
        if (plan.flatpak.length) args.push("--flatpak", ...plan.flatpak);
        // Its own background job (systemd user unit kuwai-update, sleep and
        // shutdown held off): restarting or crashing the shell can't touch it.
        starter.command = args;
        resetRun();
        running = true;
        starter.running = true;
    }
    function resetRun() { log = []; result = null; runError = ""; phase = ""; phaseLabel = "Starting"; phasesSeen = []; progress = 0.02; currentLine = ""; }
    Process {
        id: starter
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null;
                try { r = JSON.parse(text); } catch (e) {}
                if (r && r.started) { follower.running = true; return; }
                root.running = false;
                root.runError = r && r.error ? r.error : "Couldn't start the update.";
                root.result = { ok: false, skipped: [], installed: [], built: [] };
            }
        }
    }
    // On start: an update already running (started before a shell restart)?
    // Rejoin it: the feed replays from the top, so the panel rebuilds itself.
    Process {
        running: true
        command: [root.bin, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { if (JSON.parse(text).running) { root.plan = { repo: true, aur: [], flatpak: [] }; root.resetRun(); root.running = true; follower.running = true; } } catch (e) {}
            }
        }
    }
    // Watchdog: the job ended without saying "done" (killed, crashed).
    Timer {
        interval: 4000; repeat: true
        running: root.running && follower.running
        onTriggered: alive.running = true
    }
    Process {
        id: alive
        command: [root.bin, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (!JSON.parse(text).running && root.running) {
                        // Give the feed a moment to deliver its last lines.
                        settle.restart();
                    }
                } catch (e) {}
            }
        }
    }
    Timer {
        id: settle
        interval: 1500
        onTriggered: if (root.running) {
            if (!root.result) { root.runError = root.runError || "The update job stopped before finishing (see the log)."; }
            root.finishRun();
        }
    }
    function finishRun() {
        follower.running = false;
        running = false;
        progress = 1;
        if (!result) result = { ok: false, skipped: [], installed: [], built: [] };
        reviews = ({});
        excluded = ({});
        Qt.callLater(check);
    }
    // Rough weights for one ring: Arch packages 0.05–0.6, builds 0.6–0.9, install 0.9–0.98.
    function place(ev) {
        const hasAur = plan.aur.length > 0;
        const repoEnd = hasAur ? 0.6 : 0.97;
        if (ev.e === "progress" && ev.phase === "repo") progress = 0.05 + (repoEnd - 0.05) * ev.k / Math.max(1, ev.n);
        else if (ev.e === "phase" && ev.id === "build") progress = Math.max(progress, 0.6 + 0.3 * ((ev.k || 1) - 1) / Math.max(1, ev.n || 1));
        else if (ev.e === "phase" && ev.id === "install") progress = Math.max(progress, 0.9);
        else if (ev.e === "progress" && ev.phase === "install") progress = 0.9 + 0.08 * ev.k / Math.max(1, ev.n);
        else if (ev.e === "phase" && ev.id === "after") progress = Math.max(progress, 0.98);
    }
    Process {
        id: follower
        command: ["tail", "-n", "+1", "-F", (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice/update.jsonl"]
        stdout: SplitParser {
            onRead: line => {
                let ev = null;
                try { ev = JSON.parse(line); } catch (e) { return; }
                root.place(ev);
                if (ev.e === "log") {
                    root.currentLine = ev.line;
                    const l = root.log.length >= 400 ? root.log.slice(-399) : root.log.slice();
                    l.push(ev.line);
                    root.log = l;
                } else if (ev.e === "phase") {
                    root.phase = ev.id;
                    root.phaseLabel = ev.label;
                    if (root.phasesSeen.indexOf(ev.id) < 0) root.phasesSeen = [...root.phasesSeen, ev.id];
                } else if (ev.e === "error") {
                    root.runError = ev.msg;
                } else if (ev.e === "done") {
                    root.result = ev;
                    if (ev.repo === null && root.plan.repo && !ev.installed.length) root.plan = Object.assign({}, root.plan);
                    Qt.callLater(root.finishRun);
                }
            }
        }
    }
    function openLog() {
        if (result && result.log) Quickshell.execDetached(["xdg-open", result.log]);
    }
    function terminal() {
        // sysup in a terminal, for anything the panel leaves to paru.
        Quickshell.execDetached(["hyde-shell", "app", "system.update.sh", "up"]);
    }
    function restart() { Quickshell.execDetached(["systemctl", "reboot"]); }

    // ── Words ────────────────────────────────────────────────────────────
    function ago(ms) {
        if (!ms) return "never";
        const s = Math.max(0, (Date.now() - ms) / 1000);
        if (s < 60) return "just now";
        if (s < 3600) return Math.floor(s / 60) + " min ago";
        if (s < 86400) return Math.floor(s / 3600) + " h ago";
        return Math.floor(s / 86400) + " d ago";
    }
    // The part of a version that changed, for highlighting: [same, changed].
    function versionSplit(oldV, newV) {
        let i = 0;
        while (i < oldV.length && i < newV.length && oldV[i] === newV[i]) i++;
        // back up to a separator so "1.2.10" → "1.2.11" highlights "11", not "1"
        while (i > 0 && !/[.\-_:+]/.test(newV[i - 1])) i--;
        return [newV.slice(0, i), newV.slice(i)];
    }
}
