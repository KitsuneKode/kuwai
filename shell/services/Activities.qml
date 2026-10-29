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
}
