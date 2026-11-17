// Watches user coredumps and offers a toast → optional assistant diagnosis.
// Dedupes by coredump id; never reports upstream (user confirms in assistant).
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.services

Singleton {
    id: root

    readonly property string pollBin: Paths.bin + "/rice-crash-poll"
    readonly property string alertBin: Paths.bin + "/rice-crash-alert"

    function runDiagnose(brief) {
        if (!Settings.assistantOptIn) {
            Settings.set("seenAssistantPrompt", true);
            Island.open("settings", Screens.focusedName || "", "key", "island");
            return;
        }
        Assistant.show();
        OllamaService.enqueue(String(brief || "").slice(0, 12000));
    }

    function poll() {
        pollProc.running = true;
    }

    Process {
        id: pollProc
        command: [root.pollBin]
        stdout: SplitParser {
            onRead: line => {
                let row;
                try { row = JSON.parse(line); } catch (e) { return; }
                if (!row || !row.brief) return;
                alertProc.brief = row.brief;
                alertProc.running = true;
            }
        }
    }

    Process {
        id: alertProc
        property string brief: ""
        command: [root.alertBin, brief]
    }

    // systemd-coredump stores each dump in /var/lib/systemd/coredump (its
    // default Storage=external): that folder is watched, and a new file is
    // looked up 3 s after the last change (the journal entry coredumpctl
    // reads lands after the file), and once more 20 s later. Once at start
    // for one that came while the shell was down. Where the folder isn't
    // there (Storage=journal or none), the old check every 45 s.
    readonly property string coreDir: "/var/lib/systemd/coredump"
    property bool coreDirKnown: false
    property bool coreDirOk: false
    Process {
        running: true
        command: ["test", "-d", root.coreDir]
        onExited: code => { root.coreDirOk = code === 0; root.coreDirKnown = true; }
    }
    FileView {
        path: root.coreDirOk ? root.coreDir : ""
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: { coreSettled.restart(); coreAgain.restart(); }
    }
    Timer { id: coreSettled; interval: 3000; onTriggered: root.poll() }
    Timer { id: coreAgain; interval: 20000; onTriggered: root.poll() }
    Timer {
        interval: 45000
        repeat: true
        running: root.coreDirKnown && !root.coreDirOk
        onTriggered: root.poll()
    }
    Component.onCompleted: root.poll()
}
