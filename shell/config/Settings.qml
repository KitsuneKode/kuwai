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

    function set(key, value) { s[key] = value; }

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
        }
    }
}
