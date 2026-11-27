pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root
    property var catalog: []
    property string catalogState: ""
    property string activePack: ""
    property string failedPack: ""
    property int done: 0
    property int total: 0
    signal installed()

    function refresh() {
        if (listing.running) return;
        catalogState = "loading";
        listing.running = true;
    }
    function download(pack) {
        if (activePack || pack.installed) return;
        activePack = pack.id;
        failedPack = "";
        done = 0;
        total = pack.images.length;
        worker.command = ["setpriv", "--pdeathsig", "TERM", "--", Paths.bin + "/kuwai-wallpacks", "download", pack.id];
        worker.running = true;
    }
    Process {
        id: listing
        command: [Paths.bin + "/kuwai-wallpacks", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (Array.isArray(data)) {
                        root.catalog = data;
                        root.catalogState = "ready";
                        return;
                    }
                } catch (e) {}
                root.catalogState = "error";
            }
        }
    }
    Process {
        id: worker
        stdout: SplitParser {
            onRead: line => {
                try {
                    const progress = JSON.parse(line);
                    root.done = progress.done;
                    root.total = progress.total;
                } catch (e) {}
            }
        }
        onExited: code => {
            if (code !== 0) root.failedPack = root.activePack;
            else {
                const id = root.activePack;
                root.catalog = root.catalog.map(pack => pack.id === id ? Object.assign({}, pack, { installed: true }) : pack);
                root.installed();
            }
            root.activePack = "";
        }
    }
}
