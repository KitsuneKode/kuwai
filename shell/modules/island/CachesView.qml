import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.components.ui as Ui
import qs.services
import "../../services/cacheTools.mjs" as CacheTools
import "../../services/jobs.mjs" as Jobs
import "../../services/sizes.mjs" as Sizes

Item {
    id: cv
    property real maxHeight: Theme.panelMaxH
    implicitHeight: Math.min(col.implicitHeight + 30, maxHeight)

    property var seed: null
    property var report: null
    property bool loading: true
    property bool failed: false
    property string armed: ""
    Timer { id: disarm; interval: Theme.undoMs; onTriggered: cv.armed = "" }
    property string copied: ""
    Timer { id: copiedFor; interval: Theme.copiedMs; onTriggered: cv.copied = "" }
    property var job: null
    property string starting: ""
    readonly property string clearing: Jobs.running(job) ? job.label : starting
    property string note: ""
    readonly property var items: report && report.items ? report.items : []
    readonly property var pal: [Theme.blue, Theme.green, Theme.indigo, Theme.cyan, Theme.mint, Theme.brown, Theme.pink, Theme.gray]
    readonly property real backBytes: CacheTools.clearableBytes(items)
    readonly property string unavailableLine: CacheTools.unavailable(report)

    function load(fresh) {
        loading = true;
        failed = false;
        reader.command = [Paths.bin + "/kuwai-storage", "scan"].concat(fresh ? ["--fresh"] : []);
        reader.running = true;
    }
    function clear(item) {
        if (clearing) return;
        if (armed !== item.id) { armed = item.id; note = ""; disarm.restart(); return; }
        armed = "";
        disarm.stop();
        starting = item.id;
        starter.label = item.label;
        starter.command = [Paths.bin + "/kuwai-job", "start", "storage", item.id, "--", Paths.bin + "/kuwai-storage", "clear", item.id];
        starter.running = true;
    }
    function watch() {
        if (!watcher.running) watcher.running = true;
    }
    function labelOf(id) {
        const hit = items.find(i => i.id === id);
        return hit ? hit.label : id;
    }
    function copy(part) {
        Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "copy", part.command]);
        copied = part.id;
        copiedFor.restart();
    }
    Component.onCompleted: { if (seed) { report = seed; loading = false; } else load(false); watch(); }

    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                try { cv.report = JSON.parse(text); } catch (e) { cv.failed = !cv.report; }
                cv.loading = false;
            }
        }
        onExited: code => { if (code !== 0) { cv.failed = !cv.report; cv.loading = false; } }
    }
    Process {
        id: starter
        property string label: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) {}
                cv.starting = "";
                if (r.ok || r.busy) cv.watch();
                else cv.note = "Couldn't clear " + starter.label;
            }
        }
    }
    Process {
        id: watcher
        command: [Paths.bin + "/kuwai-job", "status", "storage"]
        stdout: StdioCollector {
            onStreamFinished: {
                cv.job = Jobs.parse(text);
                if (Jobs.running(cv.job)) { again.restart(); return; }
                if (!Jobs.unseen(cv.job)) return;
                cv.note = Jobs.storageNote(cv.job, cv.labelOf(cv.job.label));
                acker.running = true;
                cv.load(true);
            }
        }
    }
    Timer { id: again; interval: 1000; onTriggered: cv.watch() }
    Process { id: acker; command: [Paths.bin + "/kuwai-job", "ack", "storage"] }

    ScrollFade { flickable: flick }
    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight + 30
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
    Column {
        id: col
        x: 20; y: Theme.s2
        width: cv.width - 40
        spacing: 14

        Ui.Notice {
            visible: cv.failed
            glyph: "\u{f0026}"
            title: "The disk couldn't be read"
            action: "Try again"
            onActed: cv.load(true)
        }

        Item {
            width: parent.width
            height: bar.height
            visible: !!cv.report
            LinkedBar {
                id: bar
                width: parent.width
                title: "Disk"
                big: cv.report ? SystemStats.bytes(cv.report.disk.used) : ""
                caption: cv.report ? "of " + SystemStats.bytes(cv.report.disk.total) + " used · " + SystemStats.bytes(cv.report.disk.free) + " free" : ""
                total: cv.report ? Sizes.inGB(cv.report.disk.total) : 1
                unit: " GB"
                parts: {
                    if (!cv.report) return [];
                    const found = cv.items.map((i, k) => ({ label: i.label, value: Sizes.inGB(i.bytes), color: cv.pal[k % cv.pal.length],
                        detail: i.clearable ? "comes back on its own" : "check first" }));
                    const rest = Math.max(0, Sizes.inGB(cv.report.disk.used) - found.reduce((n, p) => n + p.value, 0));
                    return found.concat([{ label: "Everything else", value: rest, color: Theme.gray, detail: "your files, apps and the system" }]);
                }
            }
            Ui.Button {
                anchors { right: parent.right; top: parent.top }
                kind: "quiet"; glyph: "\u{f0450}"
                text: cv.loading ? "Measuring…" : "Rescan"
                enabled: !cv.loading
                onClicked: cv.load(true)
            }
        }

        Label {
            visible: !!cv.report
            width: parent.width
            wrapMode: Text.Wrap
            text: cv.backBytes > 0 ? SystemStats.bytes(cv.backBytes) + " of caches can be cleared: the tools that made them make them again when they need them"
                                   : "Nothing here needs clearing"
            size: Theme.tSub; color: Theme.textSecondary
        }

        Column {
            width: parent.width
            spacing: 2
            Repeater {
                model: cv.items
                Column {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property var parts: CacheTools.partRows(modelData)
                    width: parent.width
                    spacing: 0
                    Item {
                        width: parent.width
                        height: Math.max(Theme.sp(48), text.implicitHeight + Theme.s3)
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: cv.pal[row.index % cv.pal.length]
                        }
                        Column {
                            id: text
                            anchors { left: parent.left; leftMargin: 18; right: side.left; rightMargin: Theme.s3; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Label { width: parent.width; elide: Text.ElideRight; text: row.modelData.label; size: Theme.tBody; weight: Theme.wMedium }
                            Label {
                                width: parent.width; wrapMode: Text.Wrap
                                text: (row.modelData.clearable ? "Comes back on its own · " : "Check first · ") + row.modelData.why
                                size: Theme.tFootnote
                                color: row.modelData.clearable ? Theme.textTertiary : Theme.orange
                            }
                        }
                        Row {
                            id: side
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: Theme.s2
                            Label { anchors.verticalCenter: parent.verticalCenter; text: SystemStats.bytes(row.modelData.bytes); size: Theme.tSub; tabular: true; color: Theme.textSecondary }
                            Ui.Button {
                                visible: row.modelData.clearable
                                anchors.verticalCenter: parent.verticalCenter
                                height: Theme.sp(28); size: Theme.tSub
                                text: cv.clearing === row.modelData.id ? "Clearing…" : cv.armed === row.modelData.id ? "Clear " + SystemStats.bytes(row.modelData.bytes) + "?" : "Clear"
                                enabled: !cv.clearing
                                onClicked: cv.clear(row.modelData)
                            }
                        }
                    }
                    Column {
                        x: 18
                        width: parent.width - 18
                        spacing: Theme.s2
                        bottomPadding: row.parts.length > 0 ? Theme.s3 : 0
                        Repeater {
                            model: row.parts
                            Item {
                                id: part
                                required property var modelData
                                width: parent.width
                                height: pcol.implicitHeight
                                Column {
                                    id: pcol
                                    anchors { left: parent.left; right: pside.left; rightMargin: Theme.s3 }
                                    spacing: 2
                                    Label { width: parent.width; wrapMode: Text.Wrap; text: part.modelData.label; size: Theme.tSub; weight: Theme.wMedium }
                                    Label {
                                        width: parent.width; wrapMode: Text.WrapAnywhere
                                        text: part.modelData.command
                                        size: Theme.tFootnote; font.family: Theme.fontMono || Theme.fontText; color: Theme.textSecondary
                                    }
                                    Label {
                                        visible: text !== ""
                                        width: parent.width; wrapMode: Text.Wrap
                                        text: part.modelData.note
                                        size: Theme.tFootnote; color: Theme.textTertiary
                                    }
                                }
                                Row {
                                    id: pside
                                    anchors { right: parent.right; top: parent.top }
                                    spacing: Theme.s2
                                    Label { anchors.verticalCenter: parent.verticalCenter; text: part.modelData.bytes < Sizes.MB ? "< 1 MB" : SystemStats.bytes(part.modelData.bytes); size: Theme.tSub; tabular: true; color: Theme.textSecondary }
                                    Ui.Button {
                                        visible: part.modelData.runnable
                                        height: Theme.sp(28); size: Theme.tSub
                                        text: cv.clearing === part.modelData.id ? "Pruning…" : cv.armed === part.modelData.id ? "Prune?" : "Prune"
                                        enabled: !cv.clearing
                                        onClicked: cv.clear(part.modelData)
                                    }
                                    Ui.Button {
                                        visible: !part.modelData.runnable
                                        kind: "quiet"
                                        height: Theme.sp(28); size: Theme.tSub
                                        text: cv.copied === part.modelData.id ? "Copied" : "Copy command"
                                        onClicked: cv.copy(part.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Label {
            visible: cv.unavailableLine !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: cv.unavailableLine
            size: Theme.tFootnote; color: Theme.textTertiary
        }

        Label {
            visible: cv.note !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: cv.note
            size: Theme.tSub; color: Theme.textSecondary
        }

        Column {
            visible: !cv.report && cv.loading
            width: parent.width
            spacing: Theme.s2
            Repeater { model: 4; Skeleton { width: parent.width; height: Theme.sp(40); radius: Theme.r2 } }
        }
    }
    }
}
