// voxtype's own Quickshell UI (the recording HUD with its waveform, the
// engine picker, meeting controls), drawn inside this shell instead of a
// second Quickshell process (~400 MB). The components are voxtype's files,
// unchanged, from ~/.local/share/voxtype/quickshell: they read the daemon's
// state file, its flag files, the audio-bridge sidecar and the style file,
// exactly as they do in voxtype's own shell.
//
// The handshake (voxtype fork, voxtype-osd-quickshell): with
// VOXTYPE_OSD_HOST=$XDG_RUNTIME_DIR/rice/voxtype-host.pid in voxtype's
// environment, its OSD launcher writes the style file and then waits while
// the process in that pid file (this shell) is alive. If this shell is gone
// for a few seconds it launches voxtype's own Quickshell again, so the
// transcription UI is never lost. This side only hosts while voxtype's own
// Quickshell isn't running, so there are never two.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.services

Scope {
    id: host

    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string dir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/voxtype/quickshell"
    readonly property string styleFile: runtime + "/voxtype/quickshell-style.json"
    property bool hosting: false
    property var parts: []

    // Announce this shell as the host (its pid; voxtype checks it's a qs).
    FileView { id: pidFile; path: host.runtime + "/rice/voxtype-host.pid"; printErrors: false }
    Process {
        running: true
        command: ["sh", "-c", "mkdir -p \"$XDG_RUNTIME_DIR/rice\"; echo $PPID"]
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
    Timer { interval: 1500; running: true; onTriggered: { probe.running = true; tidy.running = true; } }
    // A slow safety net (voxtype's own launcher also checks us at its start).
    Timer { interval: 30000; running: true; repeat: true; onTriggered: probe.running = true }

    function make(file, props) {
        const c = Qt.createComponent("file://" + dir + "/" + file);
        if (c.status !== Component.Ready) {
            console.warn("voxtype host: " + file + ": " + c.errorString());
            return null;
        }
        return c.createObject(host, props || {});
    }
    function build() {
        const state = make("voxtype-shared/StateReader.qml");
        const audio = make("voxtype-shared/AudioBridge.qml");
        const style = make("voxtype-shared/StyleLoader.qml", { styleFile: styleFile });
        if (!state || !audio || !style) { for (const p of [state, audio, style]) if (p) p.destroy(); return; }
        const osd = make("OsdSurface.qml", { audio: audio, style: style });
        if (osd) {
            osd.daemonState = Qt.binding(() => state.state);
            osd.osdSuppressed = Qt.binding(() => state.osdSuppressed);
        }
        const picker = make("EnginePicker.qml");
        const meeting = make("MeetingControls.qml");
        // Their panels take the keyboard; an island panel holding it would
        // leave them unfocused, so the island steps aside when one opens.
        for (const p of [picker, meeting]) if (p) p.openChanged.connect(() => { if (p.open && Island.panel) Island.close(); });
        parts = [state, audio, style, osd, picker, meeting].filter(p => p);
        hosting = true;
        console.info("voxtype host: drawing voxtype's UI in this shell");
    }
    function teardown() {
        for (const p of parts) p.destroy();
        parts = [];
        hosting = false;
    }
}
