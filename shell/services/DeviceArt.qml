pragma Singleton

// What an audio output really is, for the HUD: a USB DAC can't tell which
// IEMs are plugged into it, and BlueZ calls every earbud "audio-headset", so
// you say it once in ~/.config/rice/devices.json and the island shows the
// thing that matters (your IEMs, "via" the DAC), with its photo:
//
//   [ { "match": "Audiocular D07", "label": "Kiwi Ears Cadenza",
//       "via": "Audiocular D07", "image": "cadenza.png", "kind": "iem" },
//     { "match": "WF-C510", "label": "Sony WF-C510", "image": "wf-c510.png", "kind": "earbuds" } ]
//
// `match` is a case-insensitive pattern tested against the device's name.
// Images live in ~/.config/rice/devices/ (a transparent PNG, ~256 px, looks
// best); a missing one falls back to the kind's glyph.
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/rice/devices"
    property var entries: []
    property bool parsed: false
    function parse() {
        try { const d = JSON.parse(file.text()); entries = Array.isArray(d) ? d : []; } catch (e) { entries = []; }
        parsed = true;
    }
    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.config/rice/devices.json"
        // This singleton is made on first use (the device at login), before
        // `loaded` arrives: the first lookup reads the file itself.
        blockLoading: true
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse()
        onLoadFailed: { root.entries = []; root.parsed = true; }
    }
    // Which image files exist (so a missing one shows the glyph, not a hole).
    property var present: ({})
    Process {
        id: scan
        running: true
        command: ["sh", "-c", "ls -1 \"$0\" 2>/dev/null", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const f of text.split("\n")) if (f.trim()) m[f.trim()] = true;
                root.present = m;
            }
        }
    }
    onEntriesChanged: scan.running = true

    // { label, via, image (file URL or ""), kind } for a device name, or null.
    function lookup(name) {
        if (!name) return null;
        if (!parsed) parse();
        for (const e of entries) {
            if (!e || !e.match) continue;
            let hit = false;
            try { hit = new RegExp(e.match, "i").test(name); } catch (x) { hit = name.toLowerCase().indexOf(String(e.match).toLowerCase()) >= 0; }
            if (!hit) continue;
            return {
                label: e.label || name,
                via: e.via || "",
                kind: e.kind || "",
                image: e.image && present[e.image] ? "file://" + dir + "/" + e.image : ""
            };
        }
        return null;
    }
}
