pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "providers.mjs" as P

Singleton {
    id: root
    property bool agentsShown: false
    property bool usageShown: false
    property bool pinned: false
    readonly property bool wanted: agentsShown || usageShown
    property string availability: ""
    property var instances: []
    property real readAt: 0
    readonly property var byId: P.index(instances)
    readonly property var trouble: P.trouble(instances)
    readonly property var off: P.off(instances)
    readonly property var unchecked: P.unchecked(instances)
    readonly property int unreadable: instances.filter(p => p.status === "unavailable").length
    readonly property string troubleLine: P.line(trouble, p => brandLabel(p.id))

    function of(id) { return byId[String(id || "")] || null; }
    function agentOf(id) {
        const p = of(id);
        return Agents.t3Agent(p && p.driver && p.driver !== "acpRegistry" ? p.driver : id);
    }
    function brandLabel(id) { return Kittymux.agentLabel(agentOf(id)); }
    function name(id) { return P.label(of(id), brandLabel(id)); }
    function why(p) { return P.why(p); }
    function modelName(id, slug) { return P.modelName(of(id), String(slug || "")); }
    function refresh(force) {
        if (reader.running || pinned) return;
        if (!force && readAt > 0 && Date.now() - readAt < Theme.panelPollMs * 6) return;
        reader.running = true;
    }

    onWantedChanged: if (wanted) refresh(false)
    Connections {
        target: T3Code
        function onAliveChanged() { root.refresh(true); }
    }
    Process {
        id: reader
        command: [Paths.bin + "/kuwai-providers"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.readAt = Date.now();
                if (root.pinned || text.trim() === "") return;
                const d = P.parse(text);
                root.availability = d.state;
                if (JSON.stringify(d.list) !== JSON.stringify(root.instances)) root.instances = d.list;
            }
        }
    }
    Component.onCompleted: refresh(true)
}
