pragma Singleton

// The rice's settings: one JSON file every module reads
// (~/.config/rice/settings.json), written back as soon as anything changes,
// reloaded when the file changes on disk. The settings app (docs/ISLAND.md)
// will edit it; until then `rice set KEY VALUE` and the file itself do.
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property alias bar: s.bar
    readonly property alias clock24: s.clock24
    readonly property alias showSeconds: s.showSeconds
    readonly property alias restWorkspaces: s.restWorkspaces
    readonly property alias restStatus: s.restStatus
    readonly property alias hoverMedia: s.hoverMedia
    readonly property alias hoverDelay: s.hoverDelay
    readonly property alias hoverView: s.hoverView
    readonly property alias islandSplit: s.islandSplit
    readonly property alias workspaceCount: s.workspaceCount
    readonly property alias notifKeepSeenHours: s.notifKeepSeenHours
    readonly property alias islandStyle: s.islandStyle
    readonly property alias restWeather: s.restWeather
    readonly property alias weatherLocation: s.weatherLocation
    readonly property alias restMedia: s.restMedia
    readonly property alias favoriteThemes: s.favoriteThemes
    readonly property alias updatesAutoRoutine: s.updatesAutoRoutine
    readonly property alias updatesCheckHours: s.updatesCheckHours
    readonly property alias updatesFlatpak: s.updatesFlatpak
    readonly property alias updatesAnnounce: s.updatesAnnounce
    readonly property alias clipPinsFirst: s.clipPinsFirst
    readonly property alias islandRest: s.islandRest
    readonly property alias islandTucked: s.islandTucked
    readonly property alias liveOnBattery: s.liveOnBattery
    readonly property alias quickPrimary: s.quickPrimary
    readonly property alias screensaverWhen: s.screensaverWhen
    readonly property alias screensaverMins: s.screensaverMins
    readonly property alias screensaverStyle: s.screensaverStyle
    readonly property alias screensaverClip: s.screensaverClip
    readonly property alias jackMicName: s.jackMicName
    readonly property alias islandProximity: s.islandProximity
    readonly property alias notifSurface: s.notifSurface
    readonly property alias notifFullscreen: s.notifFullscreen
    readonly property alias notifToastInstantOpen: s.notifToastInstantOpen
    readonly property alias notifEngageReply: s.notifEngageReply
    readonly property alias notifRedactSensitive: s.notifRedactSensitive
    readonly property alias seenNotifC1Hint: s.seenNotifC1Hint
    readonly property alias assistantOptIn: s.assistantOptIn
    readonly property alias seenAssistantPrompt: s.seenAssistantPrompt
    readonly property alias limitAlerts: s.limitAlerts
    readonly property alias breakReminders: s.breakReminders
    readonly property alias breakMins: s.breakMins
    readonly property alias sleepReminder: s.sleepReminder
    readonly property alias sleepAt: s.sleepAt
    readonly property alias limitThreshold: s.limitThreshold
    readonly property alias idleOwner: s.idleOwner
    readonly property alias idleDimAc: s.idleDimAc
    readonly property alias idleLockAc: s.idleLockAc
    readonly property alias idleOffAc: s.idleOffAc
    readonly property alias idleSleepAc: s.idleSleepAc
    readonly property alias idleDimBattery: s.idleDimBattery
    readonly property alias idleLockBattery: s.idleLockBattery
    readonly property alias idleOffBattery: s.idleOffBattery
    readonly property alias idleSleepBattery: s.idleSleepBattery
    readonly property alias idleNoSleepWhilePlaying: s.idleNoSleepWhilePlaying
    readonly property alias highContrast: s.highContrast
    readonly property alias textScale: s.textScale

    function set(key, value) { s[key] = value; }

    // Defaults, read from this file's own declarations below (nothing kept
    // twice): Settings → a row's ↺ puts one back.
    property var defaults: ({})
    function defaultOf(key) { return defaults[key]; }
    function isDefault(key) { return !(key in defaults) || JSON.stringify(s[key]) === JSON.stringify(defaults[key]); }
    function reset(key) { if (key in defaults) s[key] = defaults[key]; }
    FileView {
        path: Quickshell.shellDir + "/config/Settings.qml"
        printErrors: false
        onLoaded: {
            const d = {};
            const re = /^ {12}property \w+ (\w+): (.+?)\s*(\/\/.*)?$/gm;
            const t = text();
            for (let m = re.exec(t); m; m = re.exec(t)) {
                const v = m[2].trim();
                try { d[m[1]] = v === "({})" ? {} : JSON.parse(v); } catch (e) {}
            }
            root.defaults = d;
        }
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/rice/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter(); }
        JsonAdapter {
            id: s
            // Which top bar: "waybar" (HyDE's, as now) or "island" (the rice's).
            property string bar: "waybar"
            // Clock & Date
            property bool clock24: true
            property bool showSeconds: false
            // Island at rest: workspace capsules and signal + battery beside the clock.
            property bool restWorkspaces: true
            property bool restStatus: true
            // Island on hover: the media card under the clock; how long to rest the pointer first (ms).
            property bool hoverMedia: true
            property int hoverDelay: 220
            // Hover shows a glance (one row; a click opens everything) or everything at once.
            property string hoverView: "glance"
            // Work in the background (agents, T3) and music stepped aside get
            // their own small pills beside the island (Apple's split island).
            property bool islandSplit: true
            // Capsules shown at least (more appear as workspaces fill).
            property int workspaceCount: 5
            // Notifications: seen ones nobody acted on clear after this many hours (0 keeps them).
            property int notifKeepSeenHours: 24
            // The island's shape: "notch" (hangs from the top edge, like a MacBook's) or "floating" (a pill below it).
            property string islandStyle: "floating"
            // Island weather chip (services/Weather): on/off and the place.
            property bool restWeather: true
            property string weatherLocation: "North Lakhimpur"
            // At rest, show what's playing (tiny art and bars) beside the island.
            property bool restMedia: true
            // Themes starred in the island's theme picker (shown first).
            property var favoriteThemes: []
            // Software Update: approve AUR changes that only move versions and
            // checksums (each one is still read and checked first); how often to
            // check; include Flatpak apps; say when new updates appear.
            property bool updatesAutoRoutine: false
            property int updatesCheckHours: 3
            property bool updatesFlatpak: true
            property bool updatesAnnounce: true
            // Clipboard: pinned cards on top (off: in their place by time, with a pin).
            property bool clipPinsFirst: false
            // The island at rest: "full" (workspaces · time · status, always) or
            // "minimal" (only what's alive; the rest when you near the top edge
            // or press Super+I).
            property string islandRest: "minimal"   // minimal (the mini notch) · full · auto
            // Tucked away (Ctrl+Alt+W, like Waybar's toggle): the island gives
            // its strip back to your windows and comes out only for what
            // matters (a notification banner, an activity, a panel) or when
            // the pointer nears the top edge.
            property bool islandTucked: false
            property string screensaverWhen: "caffeine"   // caffeine · always · off
            property int screensaverMins: 3
            property string screensaverStyle: "dusk"   // dusk · night · live · still
            property string jackMicName: "Jack microphone"   // what's on the 3.5 mm jack (a Boya): rice set jackMicName Boya
            property string screensaverClip: "smoke-soft"   // a file in ~/.local/share/rice/screensavers
            // Idle (services/Idle): seconds, 0 = never. idleOwner "hypridle" hands it back.
            property string idleOwner: "shell"
            property int idleDimAc: 240
            property int idleLockAc: 300
            property int idleOffAc: 330
            property int idleSleepAc: 0
            property int idleDimBattery: 120
            property int idleLockBattery: 180
            property int idleOffBattery: 210
            property int idleSleepBattery: 900
            property bool idleNoSleepWhilePlaying: true
            // Accessibility: brighter secondary text, stronger edges, glass near opaque;
            // and text larger by this much (1.0, 1.1, 1.2).
            property bool highContrast: false
            property real textScale: 1.0
            property string notifSurface: "one"   // one (island or toast) · both
            // In a fullscreen app (a game, a film): important = critical, warnings and
            // people you can reply to grow the notch · critical = only those · off.
            property string notifFullscreen: "important"
            // Toasts: off = tap to preview, then Open; on = one tap runs the default action.
            property bool notifToastInstantOpen: false
            property bool seenNotifC1Hint: false
            // Toasts: when engaging a replyable notification, open the reply field immediately.
            property bool notifEngageReply: true
            // Chat apps: hide message body on peek/toast/center until Open (title stays).
            property bool notifRedactSensitive: true
            // Local assistant: off until you opt in (Settings or first shortcut).
            property bool assistantOptIn: false
            property bool seenAssistantPrompt: false
            // Island: agent usage limits (services/Limits): a Moment when a
            // window crosses limitThreshold %, a mark on the notch while one is used up.
            property bool limitAlerts: true
            // Wellbeing (services/Wellbeing): a break after breakMins of
            // continuous use; past sleepAt, a calm nudge to wind down.
            property bool breakReminders: true
            property int breakMins: 50
            property bool sleepReminder: true
            property string sleepAt: "00:30"
            property int limitThreshold: 80
            property bool islandProximity: true   // nearing the island 30–60 px out reveals it (off: only the top edge)
            property string quickPrimary: "caffeine"   // the quick switch shown in the hover view
            property bool liveOnBattery: false   // live wallpaper keeps playing on battery
        }
    }
}
