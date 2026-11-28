pragma Singleton

// Compatible flat XDG JSON; validated per-key patches share the CLI writer.
import QtQuick
import Quickshell
import Quickshell.Io
import "settingsSchema.js" as Contract
import "settingsState.mjs" as SettingsState

Singleton {
    id: root
    readonly property var schema: JSON.parse(schemaFile.text())
    readonly property var defaults: Contract.defaults(schema)
    property var document: ({})
    property var _sm: SettingsState.createSettingsState()
    readonly property var queue: _sm.queue
    readonly property var activeWrite: _sm.activeWrite
    property string loadError: ""
    property string writeError: ""
    readonly property string error: [loadError, writeError].filter(x => x).join(" · ")
    readonly property bool loaded: _sm.loaded
    readonly property int generation: _sm.generation
    readonly property int readGeneration: _sm.readGeneration
    readonly property bool readBusy: _sm.readBusy
    readonly property bool needsRead: _sm.needsRead
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
    readonly property bool meetingsInIsland: value("meetingsInIsland")
    readonly property bool meetingOffers: value("meetingOffers")
    readonly property var favoriteThemes: value("favoriteThemes")
    readonly property bool updatesAutoRoutine: value("updatesAutoRoutine")
    readonly property int updatesCheckHours: value("updatesCheckHours")
    readonly property bool updatesFlatpak: value("updatesFlatpak")
    readonly property bool updatesAnnounce: value("updatesAnnounce")
    readonly property bool updatesPruneCache: value("updatesPruneCache")
    readonly property bool assistantTerminal: value("assistantTerminal")
    readonly property bool clipPinsFirst: value("clipPinsFirst")
    readonly property string islandRest: value("islandRest")
    readonly property bool islandTucked: value("islandTucked")
    readonly property string screensaverWhen: value("screensaverWhen")
    readonly property int screensaverMins: value("screensaverMins")
    readonly property string screensaverStyle: value("screensaverStyle")
    readonly property string jackMicName: value("jackMicName")
    readonly property string screensaverClip: value("screensaverClip")
    readonly property int screensaverLongMins: value("screensaverLongMins")
    readonly property bool screensaverPulse: value("screensaverPulse")
    readonly property int screensaverPhotoMins: value("screensaverPhotoMins")
    readonly property string screensaverFolder: value("screensaverFolder")
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
    readonly property bool idleScreensWhileWork: value("idleScreensWhileWork")
    readonly property string caffeineMode: value("caffeineMode")   // manual | login | work (services/Caffeine)
    readonly property bool highContrast: value("highContrast")
    readonly property real textScale: value("textScale")
    readonly property string notifSurface: value("notifSurface")
    readonly property string notifFullscreen: value("notifFullscreen")
    readonly property bool notifToastInstantOpen: value("notifToastInstantOpen")
    readonly property bool seenNotifC1Hint: value("seenNotifC1Hint")
    readonly property bool notifEngageReply: value("notifEngageReply")
    readonly property string notifPrivacy: value("notifPrivacy")
    readonly property string notifPrivateSenders: value("notifPrivateSenders")
    readonly property bool assistantOptIn: value("assistantOptIn")
    readonly property bool seenAssistantPrompt: value("seenAssistantPrompt")
    readonly property bool limitAlerts: value("limitAlerts")
    readonly property bool awayRecap: value("awayRecap")
    readonly property bool agentGlow: value("agentGlow")
    readonly property bool agentServers: value("agentServers")
    readonly property bool breakReminders: value("breakReminders")
    readonly property int breakMins: value("breakMins")
    readonly property bool sleepReminder: value("sleepReminder")
    readonly property string sleepAt: value("sleepAt")
    readonly property int limitThreshold: value("limitThreshold")
    readonly property int agentBudget: value("agentBudget")
    readonly property bool islandProximity: value("islandProximity")
    readonly property bool sweepMark: value("sweepMark")
    readonly property int sweepMinGB: value("sweepMinGB")
    readonly property string quickPrimary: value("quickPrimary")
    readonly property bool liveOnBattery: value("liveOnBattery")
    readonly property string fKeys: value("fKeys")
    readonly property string wallTransition: value("wallTransition")   // auto | shards | glass (services/WallFx)
    readonly property bool wallDayNight: value("wallDayNight")

    function value(key) {
        if (root.values && Object.prototype.hasOwnProperty.call(root.values, key)) return root.values[key];
        const contract = root.schema || JSON.parse(schemaFile.text());
        return Contract.entry(contract, key).default;
    }
    function defaultOf(key) { const e = Contract.entry(root.schema, key); return e ? e.default : undefined; }
    function isDefault(key) { return !Object.prototype.hasOwnProperty.call(root.overrides || ({}), key); }
    function sourceOf(key) { return isDefault(key) ? "Default" : "Override"; }
    function dispatch(ev) {
        const res = SettingsState.stepSettings(root._sm, ev);
        root._sm = res.state;
        for (let i = 0; i < res.effects.length; i++) {
            const eff = res.effects[i];
            if (eff.type === "drain") drain();
            else if (eff.type === "scheduleRead") readLater.restart();
            else if (eff.type === "reloadFile") file.reload();
            else if (eff.type === "acceptDocument") accept(eff.text);
            else if (eff.type === "recordLoadError") {
                if (eff.missing) { root.document = ({}); root.loadError = ""; }
                else root.loadError = "Could not read settings; previous values retained";
            } else if (eff.type === "runWriter") {
                const p = eff.patch;
                writer.command = ["timeout", "--kill-after=1", "8", Paths.bin + "/kuwai-settings", p.reset ? "reset" : "set", p.key];
                if (!p.reset) writer.command = writer.command.concat([JSON.stringify(p.value)]);
                writer.running = true;
            } else if (eff.type === "recordWriteError") {
                root.writeError = (eff.detail || "").trim() || "Could not save settings; the previous value is retained";
            }
        }
    }
    function set(key, value) {
        if (!Contract.valid(Contract.entry(schema, key), value)) { root.writeError = "Invalid value for " + key; return false; }
        root.writeError = "";
        dispatch({ type: "enqueue", patch: { key: key, value: value } });
        return true;
    }
    function reset(key) {
        if (!Contract.entry(schema, key)) return false;
        root.writeError = "";
        dispatch({ type: "enqueue", patch: { key: key, reset: true } });
        return true;
    }
    function accept(text) {
        try { root.document = Contract.parse(schema, text); root.loadError = ""; return true; }
        catch (e) { root.loadError = String(e); return false; }
    }
    function changedFile() { dispatch({ type: "fileChanged" }); }
    function readFile() {
        if (writer.running) return;
        dispatch({ type: "beginRead" });
    }
    function loadedFile(text) { dispatch({ type: "readCompleted", ok: true, text: text }); }
    function failedFile(missing) { dispatch({ type: "readCompleted", ok: false, missing: missing }); }
    function drain() {
        if (writer.running) return;
        dispatch({ type: "beginWrite" });
    }
    function finished(code, output, detail) {
        let ok = false;
        if (code === 0) {
            try { Contract.parse(schema, output); ok = true; }
            catch (e) { detail = String(e); }
        }
        dispatch({ type: "writeCompleted", ok: ok, text: output, detail: detail });
    }
    FileView {
        id: schemaFile
        path: Quickshell.shellDir + "/config/settings-schema.json"
        blockLoading: true
    }
    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/kuwai/settings.json"
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
