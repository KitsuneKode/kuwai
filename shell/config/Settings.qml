pragma Singleton

// Compatible flat XDG JSON; validated per-key patches share the CLI writer.
import QtQuick
import Quickshell
import Quickshell.Io
import "settingsSchema.js" as Contract

Singleton {
    id: root
    readonly property var schema: JSON.parse(schemaFile.text())
    readonly property var defaults: Contract.defaults(schema)
    property var document: ({})
    property var queue: []
    property var activeWrite: null
    property string loadError: ""
    property string writeError: ""
    readonly property string error: [loadError, writeError].filter(x => x).join(" · ")
    property bool loaded: false
    property int generation: 0
    property int readGeneration: 0
    property bool readBusy: true          // initial FileView load
    property bool needsRead: false
    readonly property bool pending: activeWrite !== null || queue.length > 0
    readonly property var overrides: Contract.overrides(document, activeWrite, queue)
    readonly property var values: Object.assign(Object.create(null), defaults, overrides)
    readonly property string bar: value("bar")
    readonly property bool clock24: value("clock24")
    readonly property bool showSeconds: value("showSeconds")
    readonly property bool restWorkspaces: value("restWorkspaces")
    readonly property bool restStatus: value("restStatus")
    readonly property bool hoverMedia: value("hoverMedia")
    readonly property int hoverDelay: value("hoverDelay")
    readonly property string hoverView: value("hoverView")
    readonly property bool islandSplit: value("islandSplit")
    readonly property int workspaceCount: value("workspaceCount")
    readonly property int notifKeepSeenHours: value("notifKeepSeenHours")
    readonly property string islandStyle: value("islandStyle")
    readonly property bool restWeather: value("restWeather")
    readonly property string weatherLocation: value("weatherLocation")
    readonly property bool restMedia: value("restMedia")
    readonly property var favoriteThemes: value("favoriteThemes")
    readonly property bool updatesAutoRoutine: value("updatesAutoRoutine")
    readonly property int updatesCheckHours: value("updatesCheckHours")
    readonly property bool updatesFlatpak: value("updatesFlatpak")
    readonly property bool updatesAnnounce: value("updatesAnnounce")
    readonly property bool clipPinsFirst: value("clipPinsFirst")
    readonly property string islandRest: value("islandRest")
    readonly property bool islandTucked: value("islandTucked")
    readonly property string screensaverWhen: value("screensaverWhen")
    readonly property int screensaverMins: value("screensaverMins")
    readonly property string screensaverStyle: value("screensaverStyle")
    readonly property string jackMicName: value("jackMicName")
    readonly property string screensaverClip: value("screensaverClip")
    readonly property string idleOwner: value("idleOwner")
    readonly property int idleDimAc: value("idleDimAc")
    readonly property int idleLockAc: value("idleLockAc")
    readonly property int idleOffAc: value("idleOffAc")
    readonly property int idleSleepAc: value("idleSleepAc")
    readonly property int idleDimBattery: value("idleDimBattery")
    readonly property int idleLockBattery: value("idleLockBattery")
    readonly property int idleOffBattery: value("idleOffBattery")
    readonly property int idleSleepBattery: value("idleSleepBattery")
    readonly property bool idleNoSleepWhilePlaying: value("idleNoSleepWhilePlaying")
    readonly property string caffeineMode: value("caffeineMode")   // manual | login | work (services/Caffeine)
    readonly property bool highContrast: value("highContrast")
    readonly property real textScale: value("textScale")
    readonly property string notifSurface: value("notifSurface")
    readonly property string notifFullscreen: value("notifFullscreen")
    readonly property bool notifToastInstantOpen: value("notifToastInstantOpen")
    readonly property bool seenNotifC1Hint: value("seenNotifC1Hint")
    readonly property bool notifEngageReply: value("notifEngageReply")
    readonly property bool notifRedactSensitive: value("notifRedactSensitive")
    readonly property bool assistantOptIn: value("assistantOptIn")
    readonly property bool seenAssistantPrompt: value("seenAssistantPrompt")
    readonly property bool limitAlerts: value("limitAlerts")
    readonly property bool breakReminders: value("breakReminders")
    readonly property int breakMins: value("breakMins")
    readonly property bool sleepReminder: value("sleepReminder")
    readonly property string sleepAt: value("sleepAt")
    readonly property int limitThreshold: value("limitThreshold")
    readonly property bool islandProximity: value("islandProximity")
    readonly property string quickPrimary: value("quickPrimary")
    readonly property bool liveOnBattery: value("liveOnBattery")
    readonly property string wallTransition: value("wallTransition")   // auto | shards | glass (services/WallFx)

    function value(key) {
        if (root.values && Object.prototype.hasOwnProperty.call(root.values, key)) return root.values[key];
        const contract = root.schema || JSON.parse(schemaFile.text());
        return Contract.entry(contract, key).default;
    }
    function defaultOf(key) { const e = Contract.entry(root.schema, key); return e ? e.default : undefined; }
    function isDefault(key) { return !Object.prototype.hasOwnProperty.call(root.overrides || ({}), key); }
    function sourceOf(key) { return isDefault(key) ? "Default" : "Override"; }
    function set(key, value) {
        if (!Contract.valid(Contract.entry(schema, key), value)) { root.writeError = "Invalid value for " + key; return false; }
        root.writeError = "";
        root.generation++;
        root.queue = root.queue.concat([{key:key, value:value}]);
        drain();
        return true;
    }
    function reset(key) {
        if (!Contract.entry(schema, key)) return false;
        root.writeError = "";
        root.generation++;
        root.queue = root.queue.concat([{key:key, reset:true}]);
        drain();
        return true;
    }
    function accept(text) {
        try { root.document = Contract.parse(schema, text); root.loadError = ""; root.loaded = true; return true; }
        catch (e) { root.loadError = String(e); root.loaded = true; return false; }
    }
    function changedFile() {
        root.generation++;
        root.needsRead = true;
        readLater.restart();
    }
    function readFile() {
        if (!root.needsRead || root.readBusy || writer.running || root.activeWrite || root.queue.length) return;
        root.needsRead = false;
        root.readBusy = true;
        root.readGeneration = root.generation;
        file.reload();
    }
    function loadedFile(text) {
        root.readBusy = false;
        if (root.readGeneration === root.generation && !root.activeWrite && !writer.running && !root.queue.length) accept(text);
        else { root.loaded = true; root.needsRead = true; }
        if (root.needsRead) readLater.restart();
        drain();
    }
    function failedFile(missing) {
        root.readBusy = false;
        root.loaded = true;
        if (root.readGeneration === root.generation && !root.activeWrite && !writer.running && !root.queue.length) {
            if (missing) { root.document = ({}); root.loadError = ""; }
            else root.loadError = "Could not read settings; previous values retained";
        } else root.needsRead = true;
        if (root.needsRead) readLater.restart();
        drain();
    }
    function drain() {
        if (!root.loaded || writer.running || root.activeWrite || !root.queue.length) return;
        root.activeWrite = root.queue[0];
        root.queue = root.queue.slice(1);
        const p = root.activeWrite;
        writer.command = ["timeout", "--kill-after=1", "8", Paths.bin + "/rice-settings", p.reset ? "reset" : "set", p.key];
        if (!p.reset) writer.command = writer.command.concat([JSON.stringify(p.value)]);
        writer.running = true;
    }
    function finished(code, output, detail) {
        const ok = code === 0 && accept(output);
        root.activeWrite = null;
        if (!ok) { root.writeError = detail.trim() || "Could not save settings; the previous value is retained"; root.queue = []; }
        // Read current disk state too: another cooperating writer may have
        // committed after this process produced its acknowledgement.
        root.needsRead = true;
        readLater.restart();
        drain();
    }
    FileView {
        id: schemaFile
        path: Quickshell.shellDir + "/config/settings-schema.json"
        blockLoading: true
    }
    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/rice/settings.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: root.changedFile()
        onLoaded: root.loadedFile(text())
        onLoadFailed: error => root.failedFile(error === FileViewError.FileNotFound)
    }
    Timer { id: readLater; interval: 32; onTriggered: root.readFile() }
    Process {
        id: writer
        stdout: StdioCollector { id: result }
        stderr: StdioCollector { id: failure }
        onExited: code => root.finished(code, result.text, failure.text)
    }
}
