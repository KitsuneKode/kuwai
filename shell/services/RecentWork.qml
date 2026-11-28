pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))) + "/kuwai/ai/recent-work.json"
    property var recentWork: []
    property bool bgWorking: false
    property var bgDone: null
    property bool pendingRequest: false
    property string draftSessionId: ""
    property bool streaming: false
    property string bgLabel: ""
    property int bgSecs: 0
    readonly property bool assistRow: recentWork.length > 0 || bgWorking

    FileView {
        path: root.path
        watchChanges: true
        printErrors: false
        onLoaded: root.apply(text())
        onFileChanged: reload()
        onLoadFailed: root.clear()
    }

    function clear() {
        recentWork = [];
        bgWorking = false;
        bgDone = null;
        pendingRequest = false;
        draftSessionId = "";
        streaming = false;
        bgLabel = "";
        bgSecs = 0;
    }

    function apply(raw) {
        try {
            const d = JSON.parse((raw || "").trim() || "{}");
            if (!d || typeof d !== "object") { clear(); return; }
            recentWork = Array.isArray(d.recentWork)
                ? d.recentWork.filter(w => !!w && typeof w === "object" && typeof w.title === "string").slice(0, 6).map(w => ({
                    sessionId: typeof w.sessionId === "string" ? w.sessionId : "",
                    title: w.title,
                    status: typeof w.status === "string" ? w.status : "done",
                    at: Number(w.at) || 0,
                }))
                : [];
            bgWorking = !!d.bgWorking;
            bgDone = d.bgDone && typeof d.bgDone === "object" ? d.bgDone : null;
            pendingRequest = !!d.pendingRequest;
            draftSessionId = typeof d.draftSessionId === "string" ? d.draftSessionId : "";
            streaming = !!d.streaming;
            bgLabel = typeof d.bgLabel === "string" ? d.bgLabel : "";
            bgSecs = d.bgSecs | 0;
        } catch (e) {
            clear();
        }
    }

    function openSession(id) {
        Assistant.show();
        if (id) Qt.callLater(() => OllamaService.switchSession(id));
    }
}