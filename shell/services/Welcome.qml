pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "welcomeNotes.mjs" as W

Singleton {
    id: root

    property string version: ""
    property string seen: ""
    property bool loaded: false
    property bool hadSettings: false
    property bool settingsChecked: false
    readonly property string mode: loaded && settingsChecked ? W.due(seen || (hadSettings ? "0.1.0" : ""), version) : ""
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/kuwai/settings.json"
        printErrors: false
        onLoaded: { if (!root.settingsChecked) root.hadSettings = true; root.settingsChecked = true; }
        onLoadFailed: root.settingsChecked = true
    }
    property var notes: []

    FileView {
        path: Paths.root + "/VERSION"
        printErrors: false
        onLoaded: root.version = text().trim()
    }
    FileView {
        id: seenFile
        path: Paths.stateHome + "/kuwai/seen-version"
        printErrors: false
        onLoaded: { root.seen = text().trim(); root.loaded = true; }
        onLoadFailed: root.loaded = true
    }
    FileView {
        id: changelog
        path: Paths.root + "/CHANGELOG.md"
        printErrors: false
        onLoaded: root.notes = W.notesFor(text(), root.version)
    }
    onVersionChanged: if (changelog.loaded) notes = W.notesFor(changelog.text(), version)
    property bool announced: false
    Timer {
        interval: 6000
        running: root.loaded && root.version !== "" && !root.announced && root.mode !== ""
        onTriggered: {
            if (Saver.locked || Saver.showing || Island.panel !== "" || Notifs.centerOpen || Notifs.fullscreenNow) { restart(); return; }
            root.announced = true;
            if (root.mode === "first") Island.open("welcome", "", "pointer");
            else Moments.show({ kind: "update", glyph: "\u{f06b0}", label: "Kuwai " + root.version, value: "What's new", ring: -1, tone: Theme.textPrimary,
                                go: () => Island.open("welcome", "", "pointer"), dismiss: () => root.markSeen() }, 8000);
        }
    }
    function markSeen() {
        if (!version || seen === version) return;
        seen = version;
        seenFile.setText(version + "\n");
    }

    readonly property string collectPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/kuwai/collect.conf"
    property string collectText: ""
    FileView {
        id: collectFile
        path: root.collectPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.collectText = text()
        onLoadFailed: root.collectText = ""
    }
    function collecting(name) { return new RegExp("^" + name + "=on$", "m").test(collectText); }
    function setCollecting(name, on) {
        Quickshell.execDetached([Paths.bin + "/kuwai-ctl", "collect", name, on ? "on" : "off"]);
    }
}
