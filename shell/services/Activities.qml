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
        command: ["sh", "-c", `f="$1/shazam-now/recognize.pid"; last=
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
    function shazamToggle() { Quickshell.execDetached([scripts + "/shazam-now.sh", "toggle"]); }
    function shazamOpen() {
        if (shazamFound && shazamFound.id) Quickshell.execDetached(["xdg-open", "music://play/s/" + shazamFound.id]);
        shazamFound = null;
    }

    // ── Privacy: who is using the microphone ─────────────────────────────
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.audio && !n.isSink)
    PwObjectTracker { objects: root.streams }
    // Our own level meters are capture streams too: not "someone listening".
    readonly property var micUsers: streams.filter(n => {
        const p = n.properties || {};
        const bin = (p["application.process.binary"] || "").toLowerCase();
        return bin !== "quickshell" && bin !== "qs" && p["stream.monitor"] !== "true" && !(p["node.name"] || "").startsWith("quickshell");
    }).map(n => (n.properties || {})["application.name"] || n.name || "An app")
    readonly property bool micInUse: micUsers.length > 0

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
