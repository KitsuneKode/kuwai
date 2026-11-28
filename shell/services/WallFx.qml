// A wallpaper change, played by the shell, on a layer that exists only while
// it plays. Three ways (Settings.wallTransition):
//   glass    the new picture grows out of the island behind a lens of glass
//            (shaders/wallreveal.frag)
//   shards   it arrives in cut pieces spreading from the island
//            (shaders/wallcut.frag, mode 0)
//   subject  its subject's outline is traced, the subject fills in, the rest
//            spreads from it (wallcut.frag mode 1; needs the picture's map
//            from bin/kuwai-wallmap, made once with the optional cut-out model)
//   auto     subject when its map is already made, else pieces and glass in
//            turn. The map is never waited for: a picture without one gets
//            pieces now and its map is made in the background for next time.
//
//   WallFx.play(path, start)   start() is what actually sets the wallpaper
//                              (kuwai-themes → HyDE's wallpaper.sh → awww),
//                              run with awww's own transition off
//
// The order is the trick (after pocket-dots' wallfx; this code is kuwai's):
//   1. loading    each screen decodes the picture awww shows now and the new
//                 one, at that screen's pixel size (nothing on screen yet)
//   2. covered    the layer appears showing the OLD picture: the same pixels
//                 awww shows, so nothing changes to the eye; start() runs and
//                 awww switches underneath, unseen
//   3. revealing  t 0 → 1: the new picture grows from the notch (0.9 s)
//   4. settling   at t = 1 the layer shows exactly the new picture; it goes
//                 once `awww query` reports the new one on every screen
// Watchdogs: decoding longer than 1.5 s → no effect, just start(); awww not
// switched 2 s after the reveal → `awww img` it ourselves, then go; anything
// stuck after 8 s → awww set, layer gone. Reduced motion: start() only.
//   qs ipc -p … call wallfx play /path/to/picture.png     (stats: last run)
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.services
import "wallOutcome.mjs" as Outcome
import "wallDayNight.mjs" as DayNight

Singleton {
    id: root

    property string phase: ""            // "" | loading | covered | revealing | settling | leaving
    property string next: ""
    property var before: ({})            // screen name → the path awww shows now
    property bool known: false           // awww has said what it shows (the layer waits for it)
    property int ready: 0
    property real t: 0
    property var startFn: null
    property double startedAt: 0
    property string lastRun: ""          // stats: "revealed 1.42 s" / "fallback: …"
    property string mode: "glass"        // what this change plays: glass | shards | contour | subject
    property string mapPath: ""          // the picture's subject map, when already made
    property int turn: 0                 // auto alternates pieces and glass
    property real seed: 0
    property real fade: 0
    property bool swapped: false
    property bool needMap: false
    property bool liveHeld: false
    property bool toLive: false
    property var frozen: ({})
    property var queued: null
    property var shownBefore: ({})
    property string failure: ""
    property var participants: []
    property var targetOutputs: []
    property var verifyTargets: []
    property bool scoped: false
    property var readyScreens: ({})
    property string nextReal: ""
    property string lastBoundary: ""
    property var pendingSun: null
    property var preparedSun: null
    readonly property bool sunBlocked: Saver.locked || Saver.screensOff || Saver.showing
        || Quickshell.screens.some(screen => Saver.isOutputOff(screen.name))

    function onSunSchedule(text) {
        let data;
        try { data = JSON.parse(String(text).trim().split("\n").pop()); } catch (e) { return; }
        if (!Settings.wallDayNight || !DayNight.newBoundary(lastBoundary, data)) return;
        lastBoundary = data.boundary;
        pendingSun = data;
        preparedSun = null;
        onDayNightReady();
    }
    function onDayNightReady() {
        if (!Settings.wallDayNight || sunBlocked || phase !== "" || queued || variantProc.running) return;
        if (preparedSun) {
            const plan = preparedSun;
            preparedSun = null;
            const tool = Paths.bin + (Hyde.present ? "/kuwai-themes" : "/kuwai-look");
            const start = () => Quickshell.execDetached(["env", "WALLPAPER_AWWW_TRANSITION_DEFAULT=none", tool, "apply-variant", plan.path, "--boundary", plan.boundary]);
            const guard = () => {
                if (!Settings.wallDayNight || plan.boundary !== lastBoundary) return false;
                if (!sunBlocked) return true;
                preparedSun = plan;
                return false;
            };
            if (plan.outputs.length) play(plan.path, start, false, plan.outputs, guard);
            else if (guard()) start();
        } else if (pendingSun) {
            variantProc.boundary = pendingSun.boundary;
            variantProc.result = "";
            variantProc.command = Hyde.present
                ? [Paths.bin + "/kuwai-themes", "variant", pendingSun.phase]
                : [Paths.bin + "/kuwai-look", "variant", pendingSun.phase, "--fetch"];
            variantProc.command = variantProc.command.concat(["--boundary", pendingSun.boundary]);
            pendingSun = null;
            variantProc.running = true;
        }
    }
    function applyVariantResult(text, boundary) {
        if (!Settings.wallDayNight || boundary !== lastBoundary) return;
        let data;
        try { data = JSON.parse(text); } catch (e) { return; }
        if (data.path && !data.current && Array.isArray(data.outputs))
            preparedSun = { path: data.path, outputs: data.outputs, boundary: boundary };
    }
    onPhaseChanged: if (phase === "") Qt.callLater(onDayNightReady)
    onSunBlockedChanged: if (!sunBlocked) onDayNightReady()
    Connections {
        target: Settings
        function onWallDayNightChanged() {
            if (!Settings.wallDayNight) {
                root.lastBoundary = "";
                root.pendingSun = null;
                root.preparedSun = null;
            }
        }
    }
    Timer {
        id: sunTimer
        interval: 60000
        repeat: true
        triggeredOnStart: true
        running: Settings.wallDayNight
        onTriggered: if (!sunProbe.running) sunProbe.running = true
    }
    Process {
        id: sunProbe
        command: ["hyprctl", "repl", "return kuwai.sun_schedule()"]
        stdout: StdioCollector { onStreamFinished: root.onSunSchedule(text) }
    }
    Process {
        id: variantProc
        property string boundary: ""
        property string result: ""
        stdout: StdioCollector { onStreamFinished: variantProc.result = text }
        onExited: code => {
            if (code === 0) root.applyVariantResult(result, boundary);
            Qt.callLater(root.onDayNightReady);
        }
    }

    function currentScreens() {
        const out = [];
        const list = Quickshell.screens || [];
        for (let i = 0; i < list.length; i++) {
            const n = list[i] && list[i].name ? String(list[i].name) : "";
            if (n && out.indexOf(n) < 0) out.push(n);
        }
        return out;
    }
    function normalizeTargets(targets) {
        if (typeof targets === "string" && targets) return [targets];
        if (!Array.isArray(targets)) return [];
        const out = [];
        for (let i = 0; i < targets.length; i++) {
            const n = String(targets[i] || "").trim();
            if (n && out.indexOf(n) < 0) out.push(n);
        }
        return out;
    }
    function awwwCommand(path, outputs) {
        const list = Array.isArray(outputs) && outputs.length ? outputs : [];
        if (list.length) return ["awww", "img", "-o", list.join(","), path, "--transition-type", "none"];
        return ["awww", "img", path, "--transition-type", "none"];
    }
    function sameParticipants(expected, actual) {
        if (!expected || !actual || expected.length !== actual.length) return false;
        for (let i = 0; i < expected.length; i++)
            if (actual.indexOf(expected[i]) < 0) return false;
        return true;
    }
    function screensChanged() {
        if (phase === "") return;
        const actual = currentScreens();
        if (scoped) {
            for (let i = 0; i < participants.length; i++)
                if (actual.indexOf(participants[i]) < 0) { bail("monitors changed"); return; }
            return;
        }
        if (!sameParticipants(participants, actual)) bail("monitors changed");
    }
    function markReady(name) {
        if (phase !== "loading" || !name || participants.indexOf(name) < 0) return;
        if (readyScreens[name]) return;
        const nextMap = Object.assign({}, readyScreens);
        nextMap[name] = true;
        readyScreens = nextMap;
        ready = Object.keys(readyScreens).length;
        if (participants.length > 0 && participants.every(n => !!readyScreens[n])) cover();
    }
    Connections {
        target: Quickshell
        function onScreensChanged() { root.screensChanged(); }
    }

    property var swapGuard: null
    function play(path, start, live, targets, guard) {
        if (!path || (guard && !guard())) return;
        if (phase !== "") {
            queued = { path: path, start: start, live: !!live, targets: targets || null, guard: guard };
            return;
        }
        const wantTargets = normalizeTargets(targets);
        // Stream callbacks from a cancelled transition can still arrive.
        // Allow the next wallpaper through immediately while they drain.
        if (liveProbe.running || query.running || check.running || mapLookup.running || Theme.reduceMotion) { if (start) start(); return; }
        const screens = currentScreens();
        const selected = wantTargets.length ? wantTargets.filter(n => screens.indexOf(n) >= 0) : screens;
        if (!selected.length) { if (start) start(); return; }
        verifyLater.stop();
        toLive = !!live;
        scoped = wantTargets.length > 0;
        swapGuard = guard || null;
        participants = selected;
        targetOutputs = scoped ? selected.slice() : [];
        verifyTargets = targetOutputs.slice();
        readyScreens = ({});
        shownBefore = ({}); failure = ""; nextReal = "";
        next = path; startFn = start; ready = 0; t = 0; before = ({}); known = false; swapped = false; needMap = false; fade = 0;
        startedAt = Date.now();
        mapPath = ""; seed = Math.random() * 100;
        phase = "loading";
        if (Theme.holdRecolor) Theme.holdRecolor(true);
        liveThumb = ""; frozen = ({});
        liveProbe.running = true;
        mapLookup.command = [Paths.bin + "/kuwai-wallmap", "--cached", path];
        mapLookup.running = true;
        loadLimit.restart();
        watchdog.restart();
    }
    function cancelTransition() {
        phase = "";
        liveHeld = false;
        startFn = null;
        swapGuard = null;
        participants = [];
        targetOutputs = [];
        scoped = false;
        readyScreens = ({});
        if (Theme.flushRecolor) Theme.flushRecolor();
        loadLimit.stop(); watchdog.stop(); settleLimit.stop();
        handOff.stop(); go.stop(); recheck.stop(); landed.stop(); after.stop();
        reveal.stop(); fadeIn.stop(); fadeOut.stop(); swap.running = false;
    }
    function bail(why) {
        const path = next, start = startFn, live = toLive, wasSwapped = swapped, outs = (targetOutputs || []).slice();
        const allowed = typeof swapGuard === "undefined" || !swapGuard || swapGuard();
        cancelTransition();
        if (!allowed) { drain(); return; }
        lastRun = "fallback: " + why;
        if (!start && !live && !wasSwapped && path) Quickshell.execDetached(awwwCommand(path, outs));
        if (start) start();
        verify();
        drain();
    }
    function drain() {
        const q = queued;
        queued = null;
        if (q) Qt.callLater(() => root.play(q.path, q.start, q.live, q.targets, q.guard));
    }

    // What awww shows now, per screen (": DP-3: 2560x1440, … image: /path").
    function parse(text) {
        return Outcome.parseShown(text);
    }
    property string liveThumb: ""
    Process {
        id: liveProbe
        command: [Paths.bin + "/kuwai-livewall", "freeze"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const l of text.split("\n")) {
                    const x = l.match(/^(\S+) (\/.+)$/);
                    if (x) m[x[1]] = x[2];
                }
                if (root.phase !== "loading") return;
                root.frozen = m;
                root.liveThumb = Object.keys(m).length ? "1" : "";
                if (root.liveThumb) root.liveHeld = true;
            }
        }
        onExited: if (root.phase === "loading") query.running = true
    }
    Process {
        id: query
        command: ["sh", "-c", 'out=$(awww query 2>/dev/null) || exit 1; printf "%s\\n" "$out" | while IFS= read -r l; do printf "%s\\n" "$l"; case "$l" in *"image: "*) o=${l#:}; o=${o#"${o%%[![:space:]]*}"}; o=${o%%:*}; p=${l#*image:}; p=${p#"${p%%[![:space:]]*}"}; r=$(realpath -e -- "$p" 2>/dev/null); [ -n "$r" ] && printf "kuwai-real %s %s\\n" "$o" "$r";; esac; done; printf "kuwai-wanted %s\\n" "$(realpath -e -- "$1" 2>/dev/null)"', "sh", root.next]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.phase !== "loading") return;
                const m = root.parse(text);
                if (!Object.keys(m).length) { if (root.phase === "loading") root.bail("awww shows nothing"); return; }
                root.nextReal = Outcome.parseWanted(text) || Outcome.normalizePath(root.next);
                root.shownBefore = root.parse(text);
                for (const k in root.frozen) m[k] = root.frozen[k];
                root.before = m;
                root.known = true;
            }
        }
        onExited: code => { if (code !== 0 && root.phase === "loading") root.bail("awww query failed"); }
    }

    // The subject map, only if it is already made (instant); a picture without
    // one starts its map in the background, for the next time it is chosen.
    Process {
        id: mapLookup
        stdout: StdioCollector { onStreamFinished: if (root.phase !== "") root.mapPath = text.trim() }
        onExited: code => { if (code === 1 && root.phase !== "") root.needMap = true; }
    }
    function pick() {
        const want = Settings.wallTransition;
        if (want === "glass" || want === "shards" || want === "contour") return want;
        if (mapPath !== "") return "subject";
        turn += 1;
        return ["shards", "contour", "glass"][turn % 3];
    }

    Timer { id: loadLimit; interval: 1500; onTriggered: if (root.phase === "loading") root.bail("decode took too long") }

    function cover() {
        loadLimit.stop();
        phase = "covered";
        fadeIn.restart();
    }
    NumberAnimation { id: fadeIn; target: root; property: "fade"; to: 1; duration: Theme.wallFadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut; onFinished: handOff.restart() }
    NumberAnimation { id: fadeOut; target: root; property: "fade"; to: 0; duration: Theme.wallFadeMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut; onFinished: root.finish("revealed") }
    // The cover is the old picture now: awww switches under it at once, and
    // the reveal plays with nothing else running.
    Timer {
        id: handOff
        interval: 16
        onTriggered: {
            if (root.swapGuard && !root.swapGuard()) { root.cancelTransition(); root.drain(); return; }
            root.swapGuard = null;
            if (root.toLive) root.liveHeld = true;
            else if (root.liveThumb) Quickshell.execDetached([Paths.bin + "/kuwai-livewall", "stop"]);
            swap.command = root.awwwCommand(root.next, root.targetOutputs);
            swap.running = true;
            if (root.startFn) { const s = root.startFn; root.startFn = null; s(); }
            go.restart();
        }
    }
    Timer {
        id: go
        interval: 32
        onTriggered: {
            root.mode = root.pick();
            root.phase = "revealing";
            reveal.duration = root.mode === "glass" ? Theme.wallRevealMs : Theme.wallCutMs;
            reveal.easing.bezierCurve = root.mode === "glass" ? Theme.easeLinear : Theme.easeSine;
            reveal.restart();
        }
    }
    Process {
        id: swap
        onExited: code => { if (code === 0) landed.restart(); }
    }
    function enterSettling() {
        if (phase !== "revealing") return;
        phase = "settling";
        if (Theme.flushRecolor) Theme.flushRecolor();
        settleLimit.restart();
        if (swapped) leave();
        else if (!swap.running) check.running = true;
    }
    NumberAnimation {
        id: reveal
        target: root; property: "t"; from: 0; to: 1
        easing.type: Easing.BezierSpline
        onFinished: root.enterSettling()
    }
    function playWallpaper(path, output) {
        const bin = Paths.bin + (Hyde.present ? "/kuwai-themes" : "/kuwai-look");
        const command = ["env", "WALLPAPER_AWWW_TRANSITION_DEFAULT=none", bin,
            Hyde.present ? "wallpaper" : "set-wallpaper"];
        if (output) command.push("--output", output);
        command.push(path);
        play(path, () => Quickshell.execDetached(command), false, output ? [output] : []);
    }
    function liveOff() {
        Quickshell.execDetached([Paths.bin + "/kuwai-wall", "off"]);
    }
    function playLive(name) {
        if (!name || poster.running) return;
        poster.name = name;
        poster.command = [Paths.bin + "/kuwai-wall", "poster", name];
        poster.running = true;
    }
    Process {
        id: poster
        property string name: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                const name = poster.name;
                const start = () => Quickshell.execDetached([Paths.bin + "/kuwai-wall", "play", name]);
                if (p) root.play(p, start, true);
                else start();
            }
        }
    }
    property int frames: 0
    property real worstMs: 0
    property real fps: 0
    FrameAnimation {
        running: root.phase === "revealing"
        onRunningChanged: if (running) { root.frames = 0; root.worstMs = 0; root.fps = 0; }
        onTriggered: {
            root.frames += 1;
            if (root.frames > 1) root.worstMs = Math.max(root.worstMs, frameTime * 1000);
            root.fps = elapsedTime > 0 ? root.frames / elapsedTime : 0;
        }
    }
    function leave() {
        if (phase !== "settling") return;
        settleLimit.stop();
        if (Theme.flushRecolor) Theme.flushRecolor();
        phase = "leaving";
        if (startFn) startFn();
        startFn = null;
        liveHeld = false;
        fadeOut.restart();
    }
    // At t = 1 the layer is the new picture; it may go once awww is too.
    Process {
        id: check
        command: ["sh", "-c", 'awww query 2>/dev/null | while IFS= read -r l; do printf "%s\\n" "$l"; case "$l" in *"image: "*) o=${l#:}; o=${o#"${o%%[![:space:]]*}"}; o=${o%%:*}; p=${l#*image:}; p=${p#"${p%%[![:space:]]*}"}; r=$(realpath -e -- "$p" 2>/dev/null); [ -n "$r" ] && printf "kuwai-real %s %s\\n" "$o" "$r";; esac; done; printf "kuwai-wanted %s\\n" "$(realpath -e -- "$1" 2>/dev/null)"', "sh", root.next]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.phase !== "settling") return;
                const now = root.parse(text);
                const want = Outcome.parseWanted(text) || root.nextReal || Outcome.normalizePath(root.next);
                const targets = root.participants.length ? root.participants : Object.keys(now);
                const done = targets.length > 0 && targets.every(k => now[k] && now[k] === want);
                if (done) { root.swapped = true; root.leave(); }
                else recheck.restart();
            }
        }
    }
    Timer { id: recheck; interval: 120; onTriggered: if (root.phase === "settling") check.running = true }
    Timer { id: landed; interval: 40; onTriggered: { root.swapped = true; if (root.phase === "settling") root.leave(); } }
    Timer { id: settleLimit; interval: 4000; onTriggered: if (root.phase === "settling") root.force("awww hadn't switched") }

    function force(why) {
        const outs = (targetOutputs || []).slice();
        Quickshell.execDetached(awwwCommand(next, outs));
        if (startFn) startFn();
        startFn = null;
        liveHeld = false;
        lastRun = "forced: " + why;
        verify();
        after.restart();
    }
    Timer { id: after; interval: 300; onTriggered: { root.cancelTransition(); root.drain(); } }
    function finish(how) {
        lastRun = how + " (" + mode + ") " + ((Date.now() - startedAt) / 1000).toFixed(2) + " s";
        const map = needMap ? next : "";
        cancelTransition();
        verify();
        if (queued) drain();
        else if (map) Apps.run(["nice", "-n", "19", Paths.bin + "/kuwai-wallmap", map]);
    }
    function unreadable(path) {
        Qt.callLater(() => {
            if (root.phase === "" || root.next !== path) return;
            root.failure = "unreadable";
            root.bail("can't read the new picture");
        });
    }
    function decodeFailed(path) {
        Qt.callLater(() => {
            if (root.phase === "") return;
            root.bail("can't read the current picture");
        });
    }
    function verify() {
        if (toLive || !next || !Object.keys(shownBefore).length) return;
        verifier.path = next; verifier.before = shownBefore; verifier.why = failure; verifier.tries = 0;
        verifier.targets = typeof verifyTargets !== "undefined" && Array.isArray(verifyTargets) ? verifyTargets.slice() : [];
        verifyLater.restart();
    }
    function verified(text) {
        if (root.phase !== "") return;
        const wanted = Outcome.parseWanted(text);
        if (!Outcome.unchanged(verifier.before, parse(text), wanted, verifier.targets)) return;
        if (++verifier.tries < 4) { verifyLater.restart(); return; }
        lastRun += " · unchanged";
        Moments.show({ kind: "note", glyph: "\u{f02ee}", label: Outcome.sentence(verifier.why), value: "", ring: -1, tone: Theme.textPrimary }, 3200);
    }
    Timer { id: verifyLater; interval: 2500; onTriggered: if (root.phase === "" && !verifier.running) verifier.running = true }
    Process {
        id: verifier
        property string path: ""
        property var before: ({})
        property var targets: []
        property string why: ""
        property int tries: 0
        command: ["sh", "-c", 'awww query 2>/dev/null | while IFS= read -r l; do printf "%s\\n" "$l"; case "$l" in *"image: "*) o=${l#:}; o=${o#"${o%%[![:space:]]*}"}; o=${o%%:*}; p=${l#*image:}; p=${p#"${p%%[![:space:]]*}"}; r=$(realpath -e -- "$p" 2>/dev/null); [ -n "$r" ] && printf "kuwai-real %s %s\\n" "$o" "$r";; esac; done; printf "kuwai-wanted %s\\n" "$(realpath -e -- "$1" 2>/dev/null)"', "sh", path]
        stdout: StdioCollector { onStreamFinished: root.verified(text) }
    }
    Timer { id: watchdog; interval: 8000; onTriggered: if (root.phase !== "") { if (root.startFn) root.bail("stuck before the hand-off"); else root.force("stuck"); } }

    IpcHandler {
        target: "wallfx"
        function play(path: string): void { root.playWallpaper(path, ""); }
        function playOutput(output: string, path: string): void {
            if (output) root.playWallpaper(path, output);
        }
        function live(name: string): void { root.playLive(name); }
        function liveOff(): void { root.liveOff(); }
        function stats(): string { return JSON.stringify({ phase: root.phase, lastRun: root.lastRun, frames: root.frames, fps: Math.round(root.fps), worstMs: Math.round(root.worstMs) }); }
    }

    // The layer: one per screen, only while a change plays.
    LazyLoader {
        active: root.phase !== "" && root.known
        Variants {
            model: Quickshell.screens
            PanelWindow {
                id: w
                required property var modelData
                screen: modelData
                readonly property bool participating: root.participants.indexOf(modelData.name) >= 0
                readonly property real dpr: modelData.devicePixelRatio || 1
                readonly property string oldPath: root.before[modelData.name] || root.next
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                mask: Region {}
                WlrLayershell.namespace: "kuwai.wallfx"
                WlrLayershell.layer: WlrLayer.Bottom
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                // Nothing on screen until both pictures are decoded (the cover
                // must be the old picture from its first frame).
                visible: root.phase !== "loading" && participating
                property bool counted: false
                function crop(img) {
                    const iw = img.implicitWidth, ih = img.implicitHeight;
                    if (!iw || !ih || !width || !height) return Qt.vector4d(0, 0, 1, 1);
                    const ia = iw / ih, sa = width / height;
                    if (ia > sa) { const k = sa / ia; return Qt.vector4d((1 - k) / 2, 0, k, 1); }
                    const k = ia / sa;
                    return Qt.vector4d(0, (1 - k) / 2, 1, k);
                }
                readonly property vector4d cropA: crop(a)
                readonly property vector4d cropB: crop(b)
                function check() {
                    if (!participating || counted || a.status !== Image.Ready || b.status !== Image.Ready) return;
                    counted = true;
                    root.markReady(modelData.name);
                }
                // awww crops to fill, centred: the same here, at device pixels.
                Image {
                    id: a
                    anchors.fill: parent
                    visible: false
                    source: w.participating && w.oldPath ? "file://" + w.oldPath : ""
                    sourceSize: Qt.size(Math.round(w.width * w.dpr), Math.round(w.height * w.dpr))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    onStatusChanged: {
                        if (status === Image.Error) { root.decodeFailed(w.oldPath); return; }
                        w.check();
                    }
                }
                Image {
                    id: b
                    anchors.fill: parent
                    visible: false
                    source: w.participating && root.next ? "file://" + root.next : ""
                    sourceSize: Qt.size(Math.round(w.width * w.dpr), Math.round(w.height * w.dpr))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    onStatusChanged: {
                        if (status === Image.Error) { root.unreadable(root.next); return; }
                        w.check();
                    }
                }
                // The subject map (mode subject): small, read at the screen's size.
                Image {
                    id: om
                    anchors.fill: parent
                    visible: false
                    source: root.mapPath ? "file://" + root.mapPath : ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                    cache: false
                }
                ShaderEffect {
                    anchors.fill: parent
                    visible: root.mode === "glass" || root.phase === "covered" || root.phase === "loading"
                    property variant before: a
                    property variant after: b
                    property vector2d size: Qt.vector2d(width, height)
                    property vector2d origin: Qt.vector2d(width / 2, -12)     // the notch
                    property real t: root.mode === "glass" ? root.t : 0
                    property vector4d cropA: w.cropA
                    property vector4d cropB: w.cropB
                    opacity: root.fade
                    fragmentShader: Qt.resolvedUrl("../shaders/wallreveal.frag.qsb")
                }
                ShaderEffect {
                    anchors.fill: parent
                    visible: root.mode !== "glass" && (root.phase === "revealing" || root.phase === "settling" || root.phase === "leaving")
                    property variant before: a
                    property variant after: b
                    property variant order: om
                    property vector2d size: Qt.vector2d(width, height)
                    property vector2d origin: Qt.vector2d(width / 2, -12)
                    property real t: root.t
                    // A map that hasn't loaded on this screen: pieces instead.
                    property real mode: root.mode === "contour" ? 2 : root.mode === "subject" && om.status === Image.Ready ? 1 : 0
                    property real seed: root.seed
                    property vector4d cropA: w.cropA
                    property vector4d cropB: w.cropB
                    opacity: root.fade
                    fragmentShader: Qt.resolvedUrl("../shaders/wallcut.frag.qsb")
                }
            }
        }
    }
}
