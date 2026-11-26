pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "links.mjs" as Links

Singleton {
    id: root

    property var raw: ({})
    property real now: Date.now()
    readonly property var items: Object.keys(raw).map(k => Object.assign({ name: k }, raw[k]))
        .filter(c => c && c.text && (c.until || 0) * 1000 > now)
        .sort((a, b) => (b.since || 0) - (a.since || 0))
    readonly property var latest: items.length ? items[0] : null

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/kuwai/capsules.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { const d = JSON.parse(text()); root.raw = d && typeof d === "object" ? d : {}; } catch (e) { root.raw = {}; } }
        onLoadFailed: root.raw = {}
    }
    Timer { interval: 15000; repeat: true; running: Object.keys(root.raw).length > 0; onTriggered: root.now = Date.now() }

    function activate() {
        const c = latest;
        if (!c) return;
        if (c.url) { if (Links.safeLink(c.url)) Apps.open(c.url); }
        else if (Array.isArray(c.run) && c.run.length) Apps.run(c.run);
    }
    function dismiss() {
        if (latest) Quickshell.execDetached([Paths.bin + "/kuwai-ext", "capsule", "clear", latest.name]);
    }
}
