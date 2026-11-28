// voxtype's own Quickshell UI (the recording HUD with its waveform, the
// engine picker, meeting controls), drawn inside this shell instead of a
// second Quickshell process (~400 MB). The components are voxtype's files,
// unchanged, from ~/.local/share/voxtype/quickshell: they read the daemon's
// state file, its flag files, the audio-bridge sidecar and the style file,
// exactly as they do in voxtype's own shell.
//
// The handshake (voxtype fork, voxtype-osd-quickshell): with
// VOXTYPE_OSD_HOST=$XDG_RUNTIME_DIR/kuwai/voxtype-host.pid in voxtype's
// environment, its OSD launcher writes the style file and then waits while
// the process in that pid file (this shell) is alive. If this shell is gone
// for a few seconds it launches voxtype's own Quickshell again, so the
// transcription UI is never lost. This side only hosts while voxtype's own
// Quickshell isn't running, so there are never two.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config
import qs.services
import "voxScreens.mjs" as VoxScreens

Scope {
    id: host

    readonly property string runtime: Paths.runtime
    readonly property string dir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/voxtype/quickshell"
    readonly property string styleFile: runtime + "/voxtype/quickshell-style.json"
    property bool hosting: false
    property bool installed: false
    FileView {
        id: stateReaderFile
        path: host.dir + "/voxtype-shared/StateReader.qml"
        watchChanges: true
        printErrors: false
        onLoaded: {
            host.installed = true;
            if (!probe.running && !host.hosting) probe.running = true;
        }
        onFileChanged: reload()
        onLoadFailed: host.installed = false
    }
    property var parts: []              // what's shared: state, audio bridge, style, picker, meeting
    property var osds: ({})             // one HUD surface per output, by name
    property var shared: null           // { state, audio, style }

    // Announce this shell as the host (its pid; voxtype checks it's a qs).
    FileView { id: pidFile; path: host.runtime + "/kuwai/voxtype-host.pid"; printErrors: false }
    Process {
        running: true
        command: ["sh", "-c", "mkdir -p \"$XDG_RUNTIME_DIR/kuwai\"; echo $PPID"]
        stdout: StdioCollector { onStreamFinished: { pidFile.setText(text.trim() + "\n"); host.announced = true; } }
    }

    // Host only while voxtype's own Quickshell isn't running.
    Process {
        id: probe
        command: ["pgrep", "-f", "^qs -p .*/voxtype/quickshell$"]
        onExited: (code, status) => {
            const theirs = code === 0;
            if (!theirs && !host.hosting) host.build();
            else if (theirs && host.hosting) host.teardown();
            // voxtype fell back to its own Quickshell while this shell was
            // away (a restart, a crash). Now that it's back, take over again:
            // stop theirs; voxtype's supervisor restarts the launcher, which
            // sees this shell alive and waits instead of drawing.
            else if (theirs && !host.hosting && host.announced) { reclaim.running = true; reprobe.restart(); }
        }
    }
    property bool announced: false
    // A Quickshell that's killed leaves its audio bridge running (theirs
    // here, this shell's at a restart): any bridge whose parent isn't a live
    // qs is one of those, idle forever.
    readonly property string sweep: 'for p in $(pgrep -f "/voxtype-audio-bridge$"); do [ "$(cat /proc/$(ps -o ppid= -p $p | tr -d " ")/comm 2>/dev/null)" = qs ] || kill $p; done'
    Process { id: reclaim; command: ["sh", "-c", 'pkill -f "^qs -p .*/voxtype/quickshell$"; sleep 1; ' + host.sweep] }
    Process { id: tidy; command: ["sh", "-c", host.sweep] }
    Timer { id: reprobe; interval: 3000; onTriggered: probe.running = true }
    Timer { interval: 1500; running: true; onTriggered: { if (host.installed) probe.running = true; tidy.running = true; } }
    // Quickshell makes $XDG_RUNTIME_DIR/quickshell/by-pid/<pid> for every
    // instance it starts: that folder is watched, so voxtype's own shell
    // starting is seen at once (it was a pgrep every 30 s for the shell's
    // life). While it's the one drawing (not hosting here), its end leaves no
    // mark there, so that wait is the only time the 30 s check runs.
    FileView {
        path: host.runtime + "/quickshell/by-pid"
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: instanceSeen.restart()
    }
    Timer { id: instanceSeen; interval: 1000; onTriggered: { if (!host.installed) stateReaderFile.reload(); else if (!probe.running) probe.running = true; } }
    Timer { interval: 30000; running: !host.hosting && host.installed; repeat: true; onTriggered: probe.running = true }

    property int generation: 0
    property bool stale: false
    property var built: ({})
    property var sigs: ({})
    function sign(key, text) {
        const next = Object.assign({}, sigs);
        next[key] = Qt.md5(text);
        sigs = next;
        changed.restart();
    }
    property string styleQml: ""
    readonly property string mirror: runtime + "/kuwai/voxtype-style.json"
    FileView {
        id: styleJson
        path: host.styleFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let c = {};
            try { c = JSON.parse(text() || "{}") || {}; } catch (e) { c = {}; }
            host.styleQml = String(c.custom_qml || "").replace(/^file:\/\//, "").replace(/\?.*$/, "");
            host.writeMirror();
        }
    }
    FileView { id: styleMirror; path: host.mirror; printErrors: false }
    function writeMirror() {
        if (generation === 0) return;
        let c = {};
        try { c = JSON.parse(styleJson.text() || "{}") || {}; } catch (e) { return; }
        if (c.custom_qml) c.custom_qml = "file://" + styleQml + "?v=" + generation;
        styleMirror.setText(JSON.stringify(c) + "\n");
    }
    FileView { id: osdSource; path: host.dir + "/OsdSurface.qml"; watchChanges: true; printErrors: false; onFileChanged: reload(); onLoaded: host.sign("osd", text()) }
    FileView { id: styleSource; path: host.styleQml; watchChanges: true; printErrors: false; onFileChanged: reload(); onLoaded: host.sign("style:" + path, text()) }
    FileView { path: host.styleQml ? host.styleQml.replace(/\/[^\/]*$/, "") : ""; preload: false; watchChanges: true; printErrors: false; onFileChanged: styleSource.reload() }
    FileView { path: host.dir; preload: false; watchChanges: true; printErrors: false; onFileChanged: osdSource.reload() }
    Timer {
        id: changed
        interval: 1000
        onTriggered: {
            if (!host.hosting) return;
            const seen = Object.assign({}, host.built);
            for (const k in host.sigs) {
                if (seen[k] === undefined) seen[k] = host.sigs[k];
                else if (seen[k] !== host.sigs[k]) host.stale = true;
            }
            host.built = seen;
            if (host.stale) quietFor.restart();
        }
    }
    readonly property bool takeOn: Activities.voxState !== "idle" && Activities.voxState !== ""
    onTakeOnChanged: if (stale) quietFor.restart()
    Timer {
        id: quietFor
        interval: 2500
        onTriggered: {
            if (!host.stale || !host.hosting) return;
            const showing = Object.keys(host.osds).some(n => host.osds[n] && host.osds[n].visible);
            if (host.takeOn || showing) { if (!host.takeOn) restart(); return; }
            host.teardown();
            host.generation++;
            reborn.restart();
        }
    }
    Timer {
        id: reborn
        interval: 300
        onTriggered: {
            host.writeMirror();
            host.stale = false;
            host.build();
            console.info("voxtype host: the HUD's files changed; built again from them");
        }
    }
    function make(file, props) {
        const c = Qt.createComponent("file://" + dir + "/" + file + (generation > 0 ? "?v=" + generation : ""));
        if (c.status !== Component.Ready) {
            console.warn("voxtype host: " + file + ": " + c.errorString());
            return null;
        }
        return c.createObject(host, props || {});
    }
    function makeOsd(scr) {
        const sh = shared;
        const osd = make("OsdSurface.qml", { audio: sh.audio, style: sh.style, screen: scr });
        if (!osd) return null;
        osd.daemonState = Qt.binding(() => sh.state.state);
        osd.osdSuppressed = Qt.binding(() => sh.state.osdSuppressed || Settings.dictationPill === "island");
        if ("session" in osd && "session" in sh.state) osd.session = Qt.binding(() => sh.state.session);
        if ("outcome" in osd && "outcome" in sh.state) osd.outcome = Qt.binding(() => sh.state.outcome);
        if ("activeOutput" in osd) {
            const name = scr.name;
            osd.activeOutput = Qt.binding(() => !Screens.focusedName || Screens.focusedName === name);
        }
        return osd;
    }
    // One surface per output, shown on the focused one, as voxtype's own
    // shell.qml does since 1.2 (the HUD follows you between monitors; hidden
    // surfaces skip their per-frame work). Older files have one surface and
    // no session/outcome: set only what the file declares. Only the outputs
    // that changed are touched (voxScreens.mjs).
    function syncOsds() {
        const now = Quickshell.screens;
        const had = {};
        for (const n in osds) had[n] = osds[n].screen;
        const p = VoxScreens.plan(had, now);
        const next = {};
        for (const n of p.keep) next[n] = osds[n];
        for (const n of p.drop) if (osds[n]) osds[n].destroy();
        for (const n of p.add) {
            const osd = makeOsd(now.find(x => x.name === n));
            if (osd) next[n] = osd;
        }
        osds = next;
        if (p.drop.length || p.add.length) console.info("voxtype host: HUD surfaces " + (p.drop.length ? "-" + p.drop.join(",") + " " : "") + (p.add.length ? "+" + p.add.join(",") : ""));
    }
    function build() {
        const state = make("voxtype-shared/StateReader.qml");
        const audio = make("voxtype-shared/AudioBridge.qml");
        const style = make("voxtype-shared/StyleLoader.qml", { styleFile: generation > 0 && styleQml ? mirror : styleFile });
        if (!state || !audio || !style) {
            for (const p of [state, audio, style]) if (p) p.destroy();
            installed = false;
            return;
        }
        shared = { state: state, audio: audio, style: style };
        osds = ({});
        syncOsds();
        const picker = make("EnginePicker.qml");
        // Their panels take the keyboard; an island panel holding it would
        // leave them unfocused, so the island steps aside when one opens.
        if (picker) picker.openChanged.connect(() => { if (picker.open && Island.panel) Island.close(); });
        parts = [state, audio, style, picker].filter(p => p);
        hosting = true;
        built = Object.assign({}, sigs);
        syncMeeting();
        console.info("voxtype host: drawing voxtype's UI in this shell");
    }
    // A monitor plugged in, out, or back from power-off (it returns as a new
    // output of the same name): once the outputs have settled, only the HUDs
    // whose output changed are made again. It was the whole UI, torn down and
    // built at once (+10–28 MB a screensaver cycle, and every surface asking
    // the GPU for memory in the same moment: the HUD died of EGL_BAD_ALLOC).
    Timer { id: screensSettle; interval: 2000; onTriggered: if (host.hosting) host.syncOsds() }
    Connections {
        target: Quickshell
        function onScreensChanged() { if (host.hosting) screensSettle.restart(); }
    }
    property var meetingView: null
    function syncMeeting() {
        const want = hosting && !Settings.meetingsInIsland;
        if (want && !meetingView) {
            meetingView = make("MeetingControls.qml");
            if (meetingView) meetingView.openChanged.connect(() => { if (host.meetingView && host.meetingView.open && Island.panel) Island.close(); });
        } else if (!want && meetingView) {
            meetingView.destroy();
            meetingView = null;
        }
    }
    Connections {
        target: Settings
        function onMeetingsInIslandChanged() { host.syncMeeting(); }
    }
    function teardown() {
        screensSettle.stop();
        if (meetingView) { meetingView.destroy(); meetingView = null; }
        for (const n in osds) osds[n].destroy();
        osds = ({});
        for (const p of parts) p.destroy();
        parts = [];
        shared = null;
        hosting = false;
    }
}
