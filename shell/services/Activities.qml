pragma Singleton

// Things happening right now that the island shows while they last (live
// activities): voxtype dictation, a Shazam listen and what it found, and
// apps using the microphone (the privacy dot, as on iOS). Recording and
// copying stay with the Clipboard service; media comes from MPRIS.
// Event-driven: voxtype's state file is watched, Shazam's pid file is
// checked by a shell builtin loop (no process per tick).
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.config

Singleton {
    id: root

    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string scripts: Quickshell.env("HOME") + "/Scripts"

    // ── voxtype ──────────────────────────────────────────────────────────
    // idle | recording | streaming | transcribing | review …
    property string voxState: "idle"
    property string voxText: ""
    property real voxSince: 0
    readonly property bool voxActive: voxState !== "idle" && voxState !== ""
    readonly property bool voxListening: voxState === "recording" || voxState === "streaming"
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
    FileView {
        path: root.runtime + "/voxtype/live_text"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.voxText = text().trim().slice(-160)
    }
    function voxToggle() { Quickshell.execDetached([scripts + "/voxtype-toggle.sh"]); }
    function voxCancel() { Quickshell.execDetached(["voxtype", "record", "cancel"]); }

    // ── Shazam ───────────────────────────────────────────────────────────
    property bool shazamListening: false
    property var shazamFound: null            // { title, artist, url } for a moment after a match
    Process {
        running: true
        command: ["setpriv", "--pdeathsig", "KILL", "--", "sh", "-c", `f="$1/shazam-now/recognize.pid"; last=
            while :; do
                s=off; if [ -s "$f" ]; then read -r p < "$f"; [ -n "$p" ] && [ -d "/proc/$p" ] && s=on; fi
                [ "$s" != "$last" ] && echo "$s" && last=$s
                sleep 1
            done`, "sh", root.runtime]
        stdout: SplitParser { onRead: line => root.shazamListening = line === "on" }
    }
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
    function shazamToggle() { Quickshell.execDetached([Paths.bin + "/rice-shazam", "toggle"]); }
    function shazamOpen() {
        if (shazamFound && shazamFound.id) Quickshell.execDetached(["xdg-open", "music://play/s/" + shazamFound.id]);
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
    // (an app, or PipeWire for one): a tiny sysfs read every 2 s, no
    // process. Who it is gets looked up once, when it turns on.
    property bool camInUse: false
    property var camHolders: []
    readonly property var camStreams: Pipewire.nodes.values.filter(n => ((n.properties || {})["media.class"] || "") === "Stream/Input/Video")
        .map(n => (n.properties || {})["application.name"] || n.name || "An app")
    readonly property var camUsers: [...new Set(camHolders.concat(camStreams))]
    property bool camKnown: false
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
    Timer { interval: 2000; repeat: true; running: true; onTriggered: camRef.reload() }
    Process {
        id: camWho
        command: ["sh", "-c", "for p in $(fuser /dev/video* 2>/dev/null); do cat /proc/$p/comm; done | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: root.camHolders = text.trim().split("\n").filter(x => x && x !== "pipewire" && x !== "wireplumber")
        }
    }
}
