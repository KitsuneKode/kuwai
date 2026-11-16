// A wallpaper change, played by the shell: the new picture grows out of the
// island over the old one (shaders/wallreveal.frag), on a layer that exists
// only while it plays.
//
//   WallFx.play(path, start)   start() is what actually sets the wallpaper
//                              (rice-themes → HyDE's wallpaper.sh → awww),
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

Singleton {
    id: root

    property string phase: ""            // "" | loading | covered | revealing | settling
    property string next: ""
    property var before: ({})            // screen name → the path awww shows now
    property bool known: false           // awww has said what it shows (the layer waits for it)
    property int ready: 0
    property real t: 0
    property var startFn: null
    property double startedAt: 0
    property string lastRun: ""          // stats: "revealed 1.42 s" / "fallback: …"

    function play(path, start) {
        if (!path) return;
        if (phase !== "" || Theme.reduceMotion) { start(); return; }
        next = path; startFn = start; ready = 0; t = 0; before = ({}); known = false;
        startedAt = Date.now();
        phase = "loading";
        query.running = true;
        loadLimit.restart();
        watchdog.restart();
    }
    function bail(why) {
        const s = startFn;
        phase = ""; startFn = null;
        lastRun = "fallback: " + why;
        loadLimit.stop(); watchdog.stop(); settleLimit.stop();
        if (s) s();
    }

    // What awww shows now, per screen (": DP-3: 2560x1440, … image: /path").
    function parse(text) {
        const m = {};
        for (const l of String(text).split("\n")) {
            const x = l.match(/^:?\s*([^:\s]+):.*image:\s*(.+)$/);
            if (x) m[x[1]] = x[2].trim();
        }
        return m;
    }
    Process {
        id: query
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = root.parse(text);
                if (!Object.keys(m).length) { if (root.phase === "loading") root.bail("awww shows nothing"); return; }
                root.before = m;
                root.known = true;
            }
        }
        onExited: code => { if (code !== 0 && root.phase === "loading") root.bail("awww query failed"); }
    }

    onReadyChanged: if (phase === "loading" && ready >= Quickshell.screens.length) cover()
    Timer { id: loadLimit; interval: 1500; onTriggered: if (root.phase === "loading") root.bail("decode took too long") }

    function cover() {
        loadLimit.stop();
        phase = "covered";
        handOff.restart();
    }
    // Two frames for the cover to be on screen before awww switches under it.
    Timer {
        id: handOff
        interval: 50
        onTriggered: {
            if (root.startFn) root.startFn();
            root.startFn = null;
            beginReveal.restart();
        }
    }
    // HyDE recolours before awww switches; the reveal waits for neither (the
    // cover holds), it just shouldn't start before the command has.
    Timer { id: beginReveal; interval: 250; onTriggered: { root.phase = "revealing"; reveal.restart(); } }
    NumberAnimation {
        id: reveal
        target: root; property: "t"; from: 0; to: 1
        duration: 900
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut
        onFinished: { root.phase = "settling"; settleLimit.restart(); check.running = true; }
    }

    // At t = 1 the layer is the new picture; it may go once awww is too.
    Process {
        id: check
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.phase !== "settling") return;
                const now = root.parse(text), want = root.next;
                const done = Object.keys(now).length > 0 && Object.keys(now).every(k => now[k] === want || now[k].endsWith("/" + want.split("/").pop()));
                if (done) root.finish("revealed");
                else recheck.restart();
            }
        }
    }
    Timer { id: recheck; interval: 250; onTriggered: if (root.phase === "settling") check.running = true }
    Timer { id: settleLimit; interval: 2000; onTriggered: if (root.phase === "settling") root.force("awww hadn't switched") }

    function force(why) {
        Quickshell.execDetached(["awww", "img", next, "--transition-type", "none"]);
        lastRun = "forced: " + why;
        after.restart();
    }
    Timer { id: after; interval: 300; onTriggered: { root.phase = ""; root.watchdog.stop(); } }
    function finish(how) {
        lastRun = how + " " + ((Date.now() - startedAt) / 1000).toFixed(2) + " s";
        phase = ""; watchdog.stop(); settleLimit.stop();
    }
    Timer { id: watchdog; interval: 8000; onTriggered: if (root.phase !== "") { if (root.startFn) root.bail("stuck before the hand-off"); else root.force("stuck"); } }

    IpcHandler {
        target: "wallfx"
        function play(path: string): void {
            root.play(path, () => Quickshell.execDetached(["env", "WALLPAPER_AWWW_TRANSITION_DEFAULT=none", Paths.bin + "/rice-themes", "wallpaper", path]));
        }
        function stats(): string { return JSON.stringify({ phase: root.phase, lastRun: root.lastRun }); }
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
                readonly property real dpr: modelData.devicePixelRatio || 1
                readonly property string oldPath: root.before[modelData.name] || root.next
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: "black"
                mask: Region {}
                WlrLayershell.namespace: "kuwai-wallfx"
                WlrLayershell.layer: WlrLayer.Bottom
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                // Nothing on screen until both pictures are decoded (the cover
                // must be the old picture from its first frame).
                visible: root.phase !== "loading"
                property bool counted: false
                function check() {
                    if (counted || a.status !== Image.Ready || b.status !== Image.Ready) return;
                    counted = true;
                    root.ready += 1;
                }
                // awww crops to fill, centred: the same here, at device pixels.
                Image {
                    id: a
                    anchors.fill: parent
                    visible: false
                    source: w.oldPath ? "file://" + w.oldPath : ""
                    sourceSize: Qt.size(Math.round(w.width * w.dpr), Math.round(w.height * w.dpr))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    onStatusChanged: w.check()
                }
                Image {
                    id: b
                    anchors.fill: parent
                    visible: false
                    source: root.next ? "file://" + root.next : ""
                    sourceSize: Qt.size(Math.round(w.width * w.dpr), Math.round(w.height * w.dpr))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    onStatusChanged: w.check()
                }
                ShaderEffect {
                    anchors.fill: parent
                    property variant before: a
                    property variant after: b
                    property vector2d size: Qt.vector2d(width, height)
                    property vector2d origin: Qt.vector2d(width / 2, -12)     // the notch
                    property real t: root.t
                    fragmentShader: Qt.resolvedUrl("../shaders/wallreveal.frag.qsb")
                }
            }
        }
    }
}
