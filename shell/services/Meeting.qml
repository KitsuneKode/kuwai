pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "meeting.mjs" as Logic
import "links.mjs" as Links

Singleton {
    id: root

    readonly property string dir: Paths.runtime + "/voxtype"
    readonly property string bin: "voxtype"
    readonly property bool hosting: Settings.meetingsInIsland

    property bool staged: false
    property var feed: Logic.empty()
    property real micLevel: -1
    property real callLevel: -1
    property string asked: ""
    property string noticeText: ""

    readonly property string status: feed.status
    readonly property bool active: Logic.active(status)
    readonly property string phase: asked === "pause" ? "pausing" : asked === "resume" ? "resuming" : asked === "stop" ? "ending" : Logic.phase(status)
    readonly property bool live: phase === "live"
    readonly property bool paused: phase === "paused"
    readonly property string title: feed.title
    readonly property real startedAt: feed.startedAt || seenAt
    property real seenAt: 0
    readonly property var segments: feed.segments
    readonly property var latest: Logic.latest(segments)
    readonly property var speakers: Logic.speakers(segments)
    readonly property bool sharing: Notifs.shareKnown && Notifs.dndMute
    readonly property bool notice: feed.notice && active
    readonly property string trouble: Logic.trackWords(feed.problemCode, feed.problem)
    readonly property bool summarizing: feed.summarizing !== ""
    readonly property var summary: feed.summary && feed.summaryFor === (feed.lastId || feed.id) ? feed.summary : null
    readonly property string lastId: feed.lastId
    readonly property string lastTitle: feed.lastTitle
    readonly property bool following: follow.running
    readonly property bool dictating: Activities.voxListening

    function elapsed(nowMs) { return startedAt > 0 ? Math.max(0, (nowMs - startedAt) / 1000) : 0; }
    function clock(nowMs) { return Logic.clock(elapsed(nowMs)); }
    function lineOf(seg, max) { return Logic.line(seg, { sharing: sharing, max: max || 140 }); }
    function nameOr(m) { return Logic.titleOr(m, "Meeting"); }
    function rowSub(m, when) { return Logic.rowSub(m, { when: when }); }
    function length(secs) { return Logic.length(secs); }
    function stamp(ms) { return Logic.clock(ms / 1000); }

    FileView {
        id: hintFile
        path: root.dir + "/meeting_state"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.hinted(Logic.hint(text()))
        onLoadFailed: root.hinted(Logic.hint(""))
    }
    FileView {
        path: root.dir
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: dirSettle.restart()
    }
    Timer {
        id: dirSettle
        interval: 200
        onTriggered: {
            hintFile.reload();
            if (root.hosting) request.reload();
        }
    }

    function hinted(h) {
        if (staged) return;
        if (Logic.active(h.status) && !follow.running) {
            if (!seenAt) seenAt = Date.now();
            follow.running = true;
        }
    }

    Process {
        id: follow
        command: ["setpriv", "--pdeathsig", "KILL", "--", root.bin, "meeting", "watch", "--json", "--levels"]
        stdout: SplitParser { onRead: line => root.take(line) }
        onRunningChanged: if (!running) { root.micLevel = -1; root.callLevel = -1; }
        onExited: if (!root.staged && root.active) retry.restart()
    }
    Timer { id: retry; interval: 5000; onTriggered: if (root.active && !follow.running) follow.running = true }
    Timer { id: letGo; interval: 3000; onTriggered: if (Logic.feedDone(root.feed, Date.now())) follow.running = false }
    Timer { interval: 60000; repeat: true; running: follow.running && !root.active; onTriggered: if (Logic.feedDone(root.feed, Date.now())) follow.running = false }
    Timer { id: askedFor; interval: 15000; onTriggered: root.asked = "" }

    function take(line) {
        const ev = Logic.parseLine(line);
        if (!ev) return;
        if (ev.event === "levels") {
            if (ev.soundcheck === true) return;
            micLevel = Logic.meter(ev.mic);
            callLevel = Logic.meter(ev.loopback);
            return;
        }
        const was = feed;
        const next = Logic.apply(feed, ev);
        if (next === was) return;
        feed = next;
        if (ev.event === "status" || ev.event === "hello") asked = "";
        if (Logic.active(next.status) && !seenAt) seenAt = Date.now();
        if (!Logic.active(next.status)) { seenAt = 0; micLevel = -1; callLevel = -1; }
        if (Logic.active(was.status) && !Logic.active(next.status)) listSoon.restart();
        if (next.notice && !noticeText) readNotice();
        if (ev.event === "summary_ready") listSoon.restart();
        if (Logic.feedDone(next, Date.now())) letGo.restart(); else letGo.stop();
    }
    Timer { id: listSoon; interval: 3000; onTriggered: if (root.listWanted) root.loadList() }

    Component {
        id: oneShot
        Process {
            id: p
            property var done: null
            property int code: -1
            property bool exited: false
            property bool read: false
            function finish() {
                if (!exited || !read) return;
                const f = done;
                done = null;
                if (f) f(code, out.text, err.text);
                destroy(1000);
            }
            stdout: StdioCollector { id: out; onStreamFinished: { p.read = true; p.finish(); } }
            stderr: StdioCollector { id: err }
            onExited: c => { p.code = c; p.exited = true; p.finish(); }
        }
    }
    function run(argv, done) {
        const p = oneShot.createObject(root, { command: argv, done: done || null });
        p.running = true;
        return p;
    }
    function voxtype(args, done) { return run([bin].concat(args), done); }

    property string enabledState: "unknown"
    function checkEnabled(then) {
        if (staged) { if (then) then(); return; }
        voxtype(["config", "get", "meeting.enabled"], (code, out) => {
            const t = String(out || "").trim();
            root.enabledState = code !== 0 && t === "" ? "missing" : t === "true" ? "on" : "off";
            if (then) then();
        });
    }
    function turnOn() {
        voxtype(["config", "set", "meeting.enabled", "true"], code => {
            root.enabledState = code === 0 ? "restart" : root.enabledState;
            if (code !== 0) root.say("Couldn't turn meetings on", Theme.red);
        });
    }
    function restartVoxtype() {
        if (Activities.voxBusy) { say("Finish dictating first", Theme.orange); return; }
        run(["systemctl", "--user", "try-restart", "voxtype.service"], code => {
            if (code === 0) root.enabledState = "on";
            else root.say("Couldn't restart voxtype", Theme.red);
        });
    }

    function say(words, tone) {
        Moments.show({ kind: "meeting", glyph: "\u{f036c}", label: words, value: "", ring: -1, tone: tone || Theme.textPrimary }, 4000);
    }

    function start(o) {
        const args = ["meeting", "start"];
        const opt = o || {};
        if (opt.from === "call" && opt.title) args.push("--window-title", String(opt.title));
        else if (opt.title) args.push("--title", String(opt.title));
        if (opt.url && Links.safeLink(opt.url)) args.push("--url", String(opt.url));
        asked = "start";
        askedFor.restart();
        voxtype(args, code => {
            root.asked = "";
            if (code === 0) { if (!follow.running) follow.running = true; return; }
            root.checkEnabled(() => root.say(root.enabledState === "off" ? "Meetings are off in voxtype" : "Couldn't start recording", Theme.red));
        });
    }
    function control(what) {
        if (staged) { stagedControl(what); return; }
        if (["pause", "resume", "stop"].indexOf(what) < 0 || !active) return;
        asked = what;
        askedFor.restart();
        voxtype(["meeting", what], code => { if (code !== 0) { root.asked = ""; root.say("Voxtype didn't answer", Theme.red); } });
    }
    function togglePause() { control(paused || status === "paused" ? "resume" : "pause"); }
    function stagedControl(what) {
        const s = Object.assign({}, feed);
        s.status = what === "pause" ? "paused" : what === "resume" ? "recording" : "idle";
        feed = s;
    }
    function readNotice() {
        voxtype(["meeting", "notice", "--json"], (code, out) => {
            try { const n = JSON.parse(out); if (n && typeof n.notice === "string") root.noticeText = n.notice; } catch (e) {}
        });
    }
    function ackNotice() {
        if (staged) { const s = Object.assign({}, feed); s.notice = false; feed = s; return; }
        voxtype(["meeting", "notice", "--ack"]);
        const s = Object.assign({}, feed);
        s.notice = false;
        feed = s;
    }

    property bool listWanted: false
    property var meetings: []
    property bool listLoaded: false
    property bool listFailed: false
    property bool listBusy: false
    function loadList() {
        if (staged) return;
        listWanted = true;
        listBusy = true;
        checkEnabled();
        voxtype(["meeting", "list", "--json", "--limit", "50"], (code, out) => {
            root.listBusy = false;
            const rows = code === 0 ? Logic.parseList(out) : null;
            root.listFailed = rows === null;
            if (rows) { root.meetings = rows; root.listLoaded = true; }
        });
    }

    readonly property var idPattern: /^(latest|[0-9a-fA-F][0-9a-fA-F-]{3,63})$/
    property var detail: null
    property string detailId: ""
    property bool detailBusy: false
    property bool detailFailed: false
    function show(id) {
        if (!idPattern.test(String(id || ""))) return;
        detailId = id;
        if (staged) return;
        detail = null;
        detailFailed = false;
        detailBusy = true;
        voxtype(["meeting", "show", String(id), "--json"], (code, out) => {
            if (root.detailId !== id) return;
            root.detailBusy = false;
            const m = code === 0 ? Logic.parseShow(out) : null;
            root.detailFailed = m === null;
            root.detail = m;
        });
    }
    function closeDetail() { detailId = ""; detail = null; detailFailed = false; }

    property string done: ""
    property string doneFor: ""
    Timer { id: doneFade; interval: Theme.undoMs; onTriggered: { root.done = ""; root.doneFor = ""; } }
    function finished(id, what) { done = what; doneFor = id; doneFade.restart(); }
    function copy(id) {
        if (!idPattern.test(String(id || ""))) return;
        if (staged) { finished(id, "copied"); return; }
        run(["sh", "-c", 'voxtype meeting export "$1" --format markdown --speakers --timestamps --metadata | wl-copy', "sh", String(id)],
            code => code === 0 ? root.finished(id, "copied") : root.say("Couldn't copy the meeting", Theme.red));
    }
    function save(id, title, startedAt) {
        if (!idPattern.test(String(id || ""))) return;
        if (staged) { finished(id, "saved"); return; }
        const name = Logic.fileName(title, startedAt).replace(/\.md$/, "");
        run(["sh", "-c", 'd=$(xdg-user-dir DOCUMENTS 2>/dev/null); [ -n "$d" ] && [ "$d" != "$HOME" ] || d="$HOME/Documents"; d="$d/Meetings"; mkdir -p "$d" || exit 1; f="$d/$2.md"; n=1; while [ -e "$f" ]; do n=$((n + 1)); f="$d/$2 $n.md"; done; voxtype meeting export "$1" --format markdown --speakers --timestamps --metadata --output "$f" && printf %s "$d"', "sh", String(id), name],
            (code, out) => {
                if (code !== 0) { root.say("Couldn't save the meeting", Theme.red); return; }
                root.savedIn = String(out || "").trim();
                root.finished(id, "saved");
            });
    }
    property string savedIn: ""
    function openSaved() { if (savedIn) Apps.open(savedIn); }
    property string armed: ""
    Timer { id: disarm; interval: Theme.undoMs; onTriggered: root.armed = "" }
    function remove(id) {
        if (!idPattern.test(String(id || "")) || id === "latest") return;
        const r = Logic.arm(armed, id);
        armed = r.armed;
        if (!r.fire) { disarm.restart(); return; }
        disarm.stop();
        if (staged) { meetings = meetings.filter(m => m.id !== id); if (detailId === id) closeDetail(); return; }
        voxtype(["meeting", "delete", String(id), "--force"], code => {
            if (code !== 0) { root.say("Couldn't delete the meeting", Theme.red); return; }
            root.meetings = root.meetings.filter(m => m.id !== id);
            if (root.detailId === id) root.closeDetail();
        });
    }

    property var offered: ({})
    FileView {
        id: offersFile
        path: Paths.stateHome + "/kuwai/meeting-offers.json"
        printErrors: false
        onLoaded: { try { root.offered = Logic.forgetOffers(JSON.parse(text()) || {}, Date.now()); } catch (e) { root.offered = ({}); } }
    }
    function remember(key) {
        const o = Object.assign({}, offered);
        o[key] = Date.now();
        offered = Logic.forgetOffers(o, Date.now());
        offersFile.setText(JSON.stringify(offered));
    }
    readonly property bool offering: Settings.meetingOffers && !staged && !active
    Timer {
        interval: 30000; repeat: true; triggeredOnStart: true
        running: root.offering && Calendar.events.length > 0
        onTriggered: root.lookCalendar()
    }
    function lookCalendar() {
        const o = Logic.offerFor(Calendar.events, Date.now(), { offered: offered, active: active, off: enabledState === "off" || enabledState === "missing" });
        if (!o) return;
        checkEnabled(() => { if (root.enabledState === "on" && !root.active) root.offer(o); });
    }
    readonly property string callers: Activities.micUsers.slice().sort().join(",")
    property string lastCallers: ""
    onCallersChanged: {
        if (callers === "") { lastCallers = ""; callSettle.stop(); return; }
        if (offering && callers !== lastCallers) callSettle.restart();
    }
    Timer { id: callSettle; interval: 6000; onTriggered: root.lookCall() }
    function lookCall() {
        if (!offering || callers === "" || callers === lastCallers || Activities.voxBusy) return;
        lastCallers = callers;
        voxtype(["meeting", "suggest", "--dry-run"], (code, out) => {
            const s = Logic.parseSuggest(out);
            if (!s.known) return;
            root.enabledState = s.enabled ? "on" : "off";
            if (!s.enabled || s.daemon || !s.prompt || root.active) return;
            const key = "call|" + s.prompt.app + "|" + s.prompt.title;
            if (root.offered[key]) return;
            root.offer({ key: key, title: s.prompt.title, app: s.prompt.app, from: "call" });
        });
    }
    function offer(o) {
        remember(o.key);
        const name = sharing || o.private ? "" : o.title;
        const heading = name || (o.from === "call" ? o.app + " call" : "A meeting is starting");
        Moments.showCard({
            key: "meeting-offer", kind: "meeting", id: Date.now(), title: heading, sub: "Record this meeting?",
            act: { secondary: ["Not now", () => {}], primary: ["Record", () => root.start(o)] }
        }, 30000);
    }

    property string shellPid: ""
    Process {
        id: whoAmI
        command: ["sh", "-c", "echo $PPID"]
        stdout: StdioCollector { onStreamFinished: { root.shellPid = text.trim(); root.writeView(); } }
    }
    readonly property bool viewShown: Island.panel === "meeting"
    onViewShownChanged: writeView()
    FileView { id: viewStateFile; path: root.dir + "/meeting-view.state"; printErrors: false; atomicWrites: true }
    Timer { interval: 10000; repeat: true; running: root.viewShown && root.hosting && !root.staged; onTriggered: root.writeView() }
    property bool viewWritten: false
    function writeView() {
        if (!hosting || staged || (!viewShown && !viewWritten)) return;
        if (!shellPid) { if (!whoAmI.running) whoAmI.running = true; return; }
        viewWritten = viewShown;
        viewStateFile.setText(Logic.viewState(viewShown, shellPid, Date.now() / 1000));
    }
    FileView {
        id: request
        path: root.hosting ? root.dir + "/meeting-view.request" : ""
        printErrors: false
        onLoaded: root.serve(text())
    }
    function serve(text) {
        Quickshell.execDetached(["rm", "-f", "--", root.dir + "/meeting-view.request"]);
        const r = Logic.viewRequest(text, Date.now());
        if (!r || !r.open) return;
        openView(r.meeting && r.meeting !== "latest" && r.meeting !== feed.id ? r.meeting : "");
    }
    property string startView: ""
    function openOn(screenName) {
        if (!hosting) { voxtype(["meeting", "view"]); return; }
        Island.open("meeting", screenName, "pointer", "island");
    }
    function openView(id) {
        if (id && idPattern.test(id)) { startView = "past"; show(id); }
        else startView = active ? "now" : "";
        if (!hosting) { voxtype(["meeting", "view"]); return; }
        Island.preview("meeting", Screens.focusedName);
    }

    function stage(state, extra) {
        const base = {
            status: "recording", id: "staged", title: "Release sync", startedAt: Date.now() - 724000, notice: false,
            segments: Logic.absorb([], [
                { id: 0, start_ms: 1410, text: "Okay, let's start the release sync.", source: "microphone", speaker_id: "You" },
                { id: 1, start_ms: 10320, text: "Great! I tested the Omarchy package this morning.", source: "loopback", speaker_id: "Remote 1", speaker_label: "Dana" },
                { id: 2, start_ms: 23040, text: "Only one. The restart banner stays visible after the daemon restarts.", source: "loopback", speaker_id: "Remote 1", speaker_label: "Dana" }
            ])
        };
        staged = state !== "off";
        follow.running = false;
        if (state === "off") { feed = Logic.empty(); micLevel = -1; callLevel = -1; return; }
        const s = Object.assign(Logic.empty(), base);
        if (state === "paused") s.status = "paused";
        if (state === "line" && extra) s.segments = Logic.absorb(s.segments, [{ id: 3, start_ms: 40000, text: extra, source: "loopback", speaker_id: "Remote 1", speaker_label: "Dana" }]);
        feed = s;
        micLevel = state === "paused" ? -1 : 0.62;
        callLevel = state === "paused" ? -1 : 0.35;
    }

    IpcHandler {
        target: "meeting"
        function open(): void { root.openView(""); }
        function start(title: string): void { if (!root.active) root.start({ title: title }); }
        function toggle(): void { if (root.viewShown) Island.close(); else root.openView(""); }
        function pause(): void { root.control("pause"); }
        function resume(): void { root.control("resume"); }
        function stop(): void { root.control("stop"); }
        function state(): string { return root.status + (root.following ? " following" : "") + (root.staged ? " staged" : ""); }
    }
}
