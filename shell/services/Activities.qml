pragma Singleton

// Things happening right now that the island shows while they last (live
// activities): voxtype dictation, a Shazam listen and what it found, and
// apps using the microphone (the privacy dot, as on iOS). Recording and
// copying stay with the Clipboard service; media comes from MPRIS.
// Event-driven: voxtype's state file and Shazam's pid file are watched
// (inotify); nothing runs at rest but the camera's sysfs read (below).
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Hyprland
import qs.config

Singleton {
    id: root

    readonly property string runtime: Paths.runtime
    readonly property string scripts: Quickshell.env("HOME") + "/.local/share/shuush/libexec"

    // ── voxtype ──────────────────────────────────────────────────────────
    // idle | recording | streaming | transcribing | review …
    property string voxState: "idle"
    property string voxText: ""
    property real voxSince: 0
    readonly property bool voxActive: voxState !== "idle" && voxState !== ""
    readonly property bool voxListening: voxState === "recording" || voxState === "streaming"
    // Taking or writing out a dictation: what holds the idle dim, lock and
    // screensaver (a state left behind, "review" say, never holds them).
    readonly property bool voxBusy: voxListening || voxState === "transcribing"
    FileView {
        path: root.runtime + "/voxtype/state"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const s = text().trim();
            if (s !== root.voxState && (s === "recording" || s === "streaming")) root.voxSince = Date.now();
            root.voxState = s || "idle";
        }
    }
    property bool voxInField: false
    FileView {
        id: inField
        path: root.runtime + "/voxtype/live_in_field"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.voxInField = true
        onLoadFailed: root.voxInField = false
    }
    FileView {
        path: root.runtime + "/voxtype/live_text"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { root.voxText = text().trim().slice(-160); inField.reload(); }
    }
    function voxToggle() { Quickshell.execDetached(["sh", "-c", 'for d in "$1" "$HOME/Scripts"; do [ -x "$d/voxtype-toggle.sh" ] && exec "$d/voxtype-toggle.sh"; done', "sh", scripts]); }
    function voxCancel() { Quickshell.execDetached(["voxtype", "record", "cancel"]); }

    // ── Shazam ───────────────────────────────────────────────────────────
    property bool shazamListening: false
    property var shazamFound: null            // { title, artist, url } for a moment after a match
    // kuwai-shazam writes its pid to recognize.pid while it listens and
    // removes it when it ends. The file is watched (its folder has to exist
    // for that, so it's made once); /proc/<pid> says the listener is alive,
    // re-read every 5 s only while listening, for one killed with -9 that
    // left its file behind (a listen lasts 45 s at most).
    property bool shazamDirReady: false
    property string shazamPid: ""
    Process {
        running: true
        command: ["mkdir", "-p", root.runtime + "/shazam-now"]
        onExited: root.shazamDirReady = true
    }
    FileView {
        path: root.shazamDirReady ? root.runtime + "/shazam-now/recognize.pid" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const p = text().trim();
            root.shazamPid = /^[0-9]+$/.test(p) ? p : "";
            if (root.shazamPid) shazamAlive.reload(); else root.shazamListening = false;
        }
        onLoadFailed: { root.shazamPid = ""; root.shazamListening = false; }
    }
    FileView {
        id: shazamAlive
        path: root.shazamPid ? "/proc/" + root.shazamPid + "/stat" : ""
        printErrors: false
        onLoaded: root.shazamListening = root.shazamPid !== ""
        onLoadFailed: root.shazamListening = false
    }
    Timer { interval: 5000; repeat: true; running: root.shazamListening; onTriggered: shazamAlive.reload() }
    property string lastKey: ""
    property bool historyRead: false
    FileView {
        path: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/shazam-now/history.jsonl"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const lines = text().trim().split("\n");
            let e = null;
            try { e = JSON.parse(lines[lines.length - 1]); } catch (err) { return; }
            const t = e.track || e;
            const key = t.key || (t.title + t.subtitle);
            if (root.historyRead && key && key !== root.lastKey) {
                root.shazamFound = { title: t.title || "", artist: t.subtitle || "", id: t.apple_id || "" };
                foundFor.restart();
            }
            root.lastKey = key;
            root.historyRead = true;
        }
    }
    Timer { id: foundFor; interval: 12000; onTriggered: root.shazamFound = null }
    function shazamToggle() { Quickshell.execDetached([Paths.bin + "/kuwai-shazam", "toggle"]); }
    function shazamOpen() {
        if (shazamFound && shazamFound.id) Apps.open("music://play/s/" + shazamFound.id);
        shazamFound = null;
    }

    // ── Privacy: who is using the microphone ─────────────────────────────
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.audio && !n.isSink)
    PwObjectTracker { objects: root.streams }

    function cleanMicLabel(n) {
        if (!n) return "";
        const p = n.properties || {};
        const raw = p["device.description"] || n.description || n.nickname || p["node.description"] || n.name || "";
        return String(raw).replace(/ (Mono|Stereo|Analog Stereo|Digital Stereo)$/, "").replace(/^Monitor of /i, "");
    }
    function streamProps(n) { return n && n.properties ? n.properties : {}; }
    function isMonitorStream(n) {
        const p = streamProps(n);
        if (p["stream.monitor"] === "true" || p["stream.monitor"] === true) return true;
        if ((p["media.role"] || "") === "Monitor") return true;
        const label = (p["node.name"] || n.name || n.description || p["media.name"] || "");
        return /^Monitor of /i.test(label) || /\.monitor$/i.test(label);
    }
    function isRiceInternalStream(n) {
        const p = streamProps(n);
        const bin = (p["application.process.binary"] || "").toLowerCase();
        const app = (p["application.name"] || "").toLowerCase();
        if (bin === "quickshell" || bin === "qs") return true;
        if ((p["node.name"] || "").startsWith("quickshell")) return true;
        if (/^voxtype|voxtype-audio-bridge|^pw-(play|record|cat)|^pipewire$/.test(bin)) return true;
        if (/^alsa plug-in \[voxtype/.test(app)) return true;
        return false;
    }
    function captureStreams() {
        return streams.filter(n => !isMonitorStream(n) && !isRiceInternalStream(n));
    }
    readonly property var voxStreams: streams.filter(n => {
        const p = streamProps(n);
        const bin = (p["application.process.binary"] || "").toLowerCase();
        const app = (p["application.name"] || "").toLowerCase();
        return !isMonitorStream(n) && (/voxtype/.test(bin) || /^alsa plug-in \[voxtype/.test(app));
    })
    readonly property var micUsers: captureStreams().map(n => {
        const p = streamProps(n);
        const raw = p["application.name"] || n.description || n.name || "An app";
        const alsa = /^ALSA plug-in \[(.+)\]$/.exec(raw);
        if (alsa) {
            const b = alsa[1];
            return b.charAt(0).toUpperCase() + b.slice(1).replace(/-audio-bridge$/, "");
        }
        return raw.replace(/^Monitor of /i, "");
    })
    // Dictation already has its own live activity — don't also flash the privacy dot.
    readonly property bool micInUse: !voxListening && micUsers.length > 0
    readonly property var mic: Pipewire.defaultAudioSource
    // Default input label (USB Boya, built-in, …). Prefer voxtype's capture device while dictating.
    readonly property string micName: {
        if (voxListening && voxStreams.length) {
            const vs = voxStreams[0];
            const fromStream = cleanMicLabel(vs);
            if (fromStream && !/^alsa plug-in/i.test(fromStream) && !/audio-bridge/i.test(fromStream)) return fromStream;
        }
        return cleanMicLabel(mic);
    }
    readonly property string micUseSummary: {
        if (voxListening) return micName ? "Dictating · " + micName : "Dictating";
        if (!micInUse) return "";
        const who = [...new Set(micUsers)].join(", ");
        return who;
    }

    // ── Privacy: who is using the camera ─────────────────────────────────
    // The UVC driver's use count goes up while anything has the camera open
    // (an app, or PipeWire for one). sysfs can't be watched (no inotify), so
    // it's read when something that comes with a camera turning on happens
    // (a window opening, closing or taking focus; a PipeWire video stream),
    // and every 5 s besides, for an app that opens it with no window: the
    // dot is for use you didn't start. One read of a tiny file, no process;
    // not while locked or the screens are off (read again on the way back).
    // Who it is gets looked up once, when it turns on.
    property bool camInUse: false
    property var camHolders: []
    readonly property var camStreams: Pipewire.nodes.values.filter(n => ((n.properties || {})["media.class"] || "") === "Stream/Input/Video")
        .map(n => (n.properties || {})["application.name"] || n.name || "An app")
    readonly property var camUsers: [...new Set(camHolders.concat(camStreams))]
    property bool camKnown: false
    readonly property bool camAwake: !Saver.locked && !Saver.screensOff
    FileView {
        id: camRef
        path: "/sys/module/uvcvideo/refcnt"
        printErrors: false
        onLoaded: {
            root.camKnown = true;
            const on = Number(text().trim()) > 0;
            if (on === root.camInUse) return;
            root.camInUse = on;
            if (on) camWho.running = true;
            else root.camHolders = [];
        }
    }
    function camCheck() { camSoon.restart(); }
    // Events come in bursts (a window opening is several): one read after.
    Timer { id: camSoon; interval: 250; onTriggered: camRef.reload() }
    Timer { interval: 5000; repeat: true; running: root.camAwake; onTriggered: camRef.reload() }
    onCamAwakeChanged: if (camAwake) camCheck()
    onCamStreamsChanged: camCheck()
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name;
            if (n === "openwindow" || n === "closewindow" || n === "activewindowv2") root.camCheck();
        }
    }
    Process {
        id: camWho
        command: ["sh", "-c", "for p in $(fuser /dev/video* 2>/dev/null); do cat /proc/$p/comm; done | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: root.camHolders = text.trim().split("\n").filter(x => x && x !== "pipewire" && x !== "wireplumber")
        }
    }
}
