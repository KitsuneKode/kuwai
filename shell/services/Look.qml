pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    readonly property string bin: Quickshell.shellDir + "/../bin/kuwai-look"
    property var themes: []
    property var wallpapers: []
    property var state: ({})
    property bool busy: runner.running
    property string error: ""
    property bool loaded: false
    signal changed()

    function refresh() {
        if (!lister.running) lister.running = true;
        if (!statProc.running) statProc.running = true;
    }

    function runCmd(args) {
        if (runner.running) return false;
        error = "";
        runner.command = [bin].concat(args);
        runner.running = true;
        return true;
    }

    function setWallpaper(path, mode) {
        const args = ["set-wallpaper", String(path)];
        if (mode) args.push("--mode", String(mode));
        return runCmd(args);
    }

    function setTheme(name) {
        return runCmd(["theme", String(name)]);
    }

    function setMode(mode) {
        return runCmd(["mode", String(mode)]);
    }

    function undo() {
        return runCmd(["undo"]);
    }

    Process {
        id: lister
        command: [root.bin, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (Array.isArray(d.themes)) root.themes = d.themes;
                    if (Array.isArray(d.wallpapers)) root.wallpapers = d.wallpapers;
                    root.loaded = true;
                } catch (e) {}
            }
        }
    }

    Process {
        id: statProc
        command: [root.bin, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d && d.state) root.state = d.state;
                } catch (e) {}
            }
        }
    }

    Process {
        id: runner
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d && d.state) root.state = d.state;
                } catch (e) {}
                Theme.reloadLook();
                root.changed();
                root.refresh();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const msg = text.trim();
                if (msg) root.error = msg;
            }
        }
    }

    IpcHandler {
        target: "look"
        function reload(): void {
            Theme.reloadLook();
            root.changed();
            root.refresh();
        }
    }
}
