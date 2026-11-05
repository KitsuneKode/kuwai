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

    Timer {
        interval: 45000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }
}
