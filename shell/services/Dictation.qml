pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.config
import "dictation.mjs" as D
import "../modules/voxtype/voxRing.mjs" as VoxRing

Singleton {
    id: root

    readonly property string dir: Paths.runtime + "/voxtype"
    readonly property string state: Activities.voxState
    readonly property bool listening: D.listening(state)
    readonly property bool hosts: Settings.dictationPill === "island"

    property string takeId: ""
    property real since: 0
    property string app: ""
    property string screen: ""
    property bool privateTake: false
    property bool fieldTake: false
    property bool wordsOpen: false
    property string final: ""
    property var ending: null
    property var pending: []
    property real now: Date.now()
    property real lastSpeech: 0
    property real lastSignal: 0
    property bool bringFailed: false
    property var level: VoxRing.quiet()
    property var hist: []
    property var bars: D.bars([])

    readonly property bool hidden: privateTake || Notifs.sharing
    property bool staged: false
    readonly property real elapsed: listening && since > 0 ? Math.max(0, now - since) : 0
    property bool muted: false
    Binding on muted { when: !root.staged; value: root.listening && !!root.heard && !!root.heard.audio && root.heard.audio.muted }
    property bool quiet: false
    Binding on quiet { when: !root.staged; value: root.listening && D.tooQuiet({ elapsed: root.elapsed, text: Activities.voxText, lastSpeech: root.lastSpeech, now: root.now }) }
    property bool silent: false
    Binding on silent { when: !root.staged; value: root.listening && D.micSilent({ feeding: voice.enabled && !!root.heard, elapsed: root.elapsed, lastSignal: root.lastSignal }) }
    readonly property string phase: D.phase({ state: state, muted: muted, silent: silent, quiet: quiet, ending: ending })
    readonly property bool onStage: phase !== ""
    readonly property bool live: D.LIVE.indexOf(phase) >= 0
    readonly property bool writing: phase === "writing"
    property bool warm: false
    Binding on warm { when: !root.staged; value: !Activities.voxActive && Activities.voxStreams.length > 0 }
    readonly property int queued: D.waiting(pending, state, takeId)
    readonly property var shown: hosts ? D.words({ phase: phase, hidden: hidden, inField: fieldTake || Activities.voxInField, open: wordsOpen, text: Activities.voxText, final: final })
                                       : ({ mode: phase === "recovered" ? "note" : "", text: phase === "recovered" ? "Click to bring it back" : "" })
    readonly property string said: bringFailed && phase === "recovered" ? "Nothing to bring back" : D.said(phase, app, ending && ending.limit ? "limit" : "")
    readonly property string saidPrivate: D.said("private-listening", app, "")
    readonly property string clock: D.clock(elapsed)
    readonly property string glyph: D.glyph(phase)
    readonly property color tone: ({ red: Theme.red, orange: Theme.orange, green: Theme.green, accent: Theme.accent, quiet: Theme.textSecondary })[D.tone(phase)]
    readonly property string fullText: hidden || fieldTake || Activities.voxInField ? "" : (live || writing ? Activities.voxText : phase === "delivered" || phase === "clipboard" ? final : "")

    function wordsHere(screenName) {
        return shown.mode !== "" && (screen === "" || screen === screenName);
    }

    property string lastState: "idle"
    Connections {
        target: Activities
        function onVoxStateChanged() {
            const s = Activities.voxState, was = root.lastState;
            root.lastState = s;
            if (D.listening(s) && !D.listening(was)) root.begin();
            if (s === "idle" || s === "") { root.pending = []; if (was !== "idle" && was !== "") endGrace.restart(); }
        }
        function onVoxInFieldChanged() { if (Activities.voxInField && Activities.voxActive) root.fieldTake = true; }
        function onVoxTextChanged() { root.gateWords(); }
    }
    Component.onCompleted: { lastState = Activities.voxState; if (listening) begin(); }

    function begin() {
        takeFile.reload();
        const id = takeFile.text().trim();
        takeId = /^[0-9]+$/.test(id) ? id : "";
        since = Activities.voxSince > 0 ? Activities.voxSince : Date.now();
        now = Date.now();
        ending = null;
        endHold.stop();
        endGrace.stop();
        final = "";
        fieldTake = Activities.voxInField;
        wordsOpen = false;
        wordsWait.stop();
        lastSpeech = 0;
        lastSignal = 0;
        bringFailed = false;
        level = VoxRing.quiet();
        hist = [];
        bars = D.bars([]);
        screen = Screens.focusedName || "";
        privateTake = sensitiveFile.present();
        targetFile.reload();
        targetFile.text();
        pending = D.started(pending, takeId, Date.now());
    }
    function gateWords() {
        if (wordsOpen || fieldTake || !Activities.voxText || !Activities.voxActive) return;
        if (!wordsWait.running) wordsWait.restart();
    }
    Timer {
        id: wordsWait
        interval: D.WORDS_WAIT_MS
        onTriggered: {
            Activities.voxRecheckField();
            if (Activities.voxInField) root.fieldTake = true;
            else root.wordsOpen = Activities.voxActive;
        }
    }
    Timer {
        id: endGrace
        interval: Theme.handoffMs * 3
        onTriggered: { outcomeFile.reload(); root.settle(outcomeFile.text()); }
    }
    function settle(raw) {
        let rec = null;
        try { rec = JSON.parse(raw || "null"); } catch (e) { rec = null; }
        if (rec && rec.take_id) pending = D.finished(pending, rec.take_id);
        if (Activities.voxActive || since <= 0) return;
        const e = D.ending(rec, { id: takeId, since: since });
        if (!e || (ending && ending.at === e.at)) return;
        if (e.kind === "delivered" || e.kind === "clipboard") finalFile.reload();
        ending = e;
        endHold.interval = D.holdFor(e.kind);
        endHold.restart();
    }
    Timer { id: endHold; onTriggered: { root.ending = null; root.bringFailed = false; } }
    onPhaseChanged: if (phase === "" && Island.panel === "dictation") Island.close()

    Timer {
        interval: 250; repeat: true; triggeredOnStart: true
        running: root.listening
        onTriggered: root.now = Date.now()
    }

    FileView { id: takeFile; path: root.dir + "/take_id"; blockLoading: true; printErrors: false }
    FileView {
        id: outcomeFile
        path: root.dir + "/outcome.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.settle(text())
    }
    FileView {
        id: finalFile
        path: root.dir + "/pp_final"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (root.hidden || root.since <= 0) return;
            const t = D.finalText(text(), root.since);
            if (t) root.final = t;
        }
    }
    FileView {
        id: sensitiveFile
        property bool here: false
        function present() { reload(); text(); return here; }
        path: root.dir + "/sensitive_field"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { here = true; if (Activities.voxActive) root.privateTake = true; }
        onLoadFailed: here = false
    }
    FileView {
        path: root.takeId ? root.dir + "/takes/" + root.takeId + "/pp_private" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.privateTake = true
    }
    FileView {
        id: targetFile
        path: root.dir + "/target_window"
        blockLoading: true
        printErrors: false
        onLoaded: {
            let w = {};
            try { w = JSON.parse(text() || "{}") || {}; } catch (e) { w = {}; }
            const cls = String(w.class || "");
            let entry = null;
            try { entry = cls ? DesktopEntries.heuristicLookup(cls) : null; } catch (e) { entry = null; }
            root.app = D.appName(cls, entry && entry.name ? entry.name : "");
        }
        onLoadFailed: root.app = ""
    }

    readonly property var heard: {
        if (!listening) return null;
        const s = Activities.voxStreams[0];
        const g = s ? Pipewire.linkGroups.values.find(l => l.target === s && l.source && !l.source.isStream) : null;
        return g ? g.source : Pipewire.defaultAudioSource;
    }
    PwObjectTracker { objects: root.heard ? [root.heard] : [] }
    PwNodePeakMonitor {
        id: voice
        node: root.heard
        enabled: root.listening && !Saver.away
    }
    Timer {
        interval: 45; repeat: true
        running: voice.enabled
        onTriggered: {
            const p = voice.peak;
            const t = Date.now();
            root.level = VoxRing.listen(root.level, p, interval);
            if (p > D.SIGNAL) root.lastSignal = t;
            if (root.level.glow > D.SPEECH) root.lastSpeech = t;
            root.hist = D.ripple(root.hist, root.level.glow);
            root.bars = D.bars(root.hist);
        }
    }

    function open(screenName) { Island.openOn("dictation", screenName || screen || Screens.focusedName, "pointer", "island"); }
    function finish() { Activities.voxToggle(); }
    function cancel() {
        Quickshell.execDetached(["sh", "-c", 's="$1/voxtype-cancel.sh"; [ -x "$s" ] && exec "$s" now; exec voxtype record cancel', "sh", Activities.scripts]);
    }
    function bringBack() { if (!recover.running) recover.running = true; }
    Process {
        id: recover
        command: ["sh", "-c", "if command -v shuush >/dev/null 2>&1; then exec shuush recover; fi; exec voxtype record recover"]
        onExited: code => {
            if (code === 0) { root.ending = null; endHold.stop(); if (Island.panel === "dictation") Island.close(); }
            else root.bringFailed = true;
        }
    }
}
