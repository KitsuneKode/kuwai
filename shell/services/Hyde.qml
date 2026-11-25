pragma Singleton

// Is HyDE here, and where its pieces are: the one place the shell asks.
// kuwai grew on HyDE (another Hyprland dotfiles project) and still uses its
// wallpaper, theme colours, emoji lists and a few of its scripts when it is
// installed; without it every one of those has a defined fallback
// (docs/design/WITHOUT-HYDE.md has the table):
//   present    HyDE's scripts are installed (~/.local/lib/hyde/globalcontrol.sh,
//              the same test Hyprland's side makes: hypr/kuwai/core.lua K.hyde)
//   hasShell   its `hyde-shell` command is on PATH
//   wallpaper  the current wallpaper's file, or "" when there is none (views
//              then show black, a shade off Hyprland's own background)
//   run(args, what)  hyde-shell ARGS; without it, says once what needs HyDE
//                    and returns false (the caller may do something else)
// Theme's colours come from HyDE's files too (config/Theme.qml, which can't
// use a service): without them Theme keeps its own defaults.
// (This header has no braces: Quickshell's scanner stops at the first one.)
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root
    readonly property string home: Quickshell.env("HOME")
    readonly property string lib: home + "/.local/lib/hyde"
    readonly property string cache: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/hyde"
    readonly property string config: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/hyde"
    readonly property string state: Paths.stateHome + "/hyde"
    readonly property string data: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/hyde"
    readonly property string wallSet: cache + "/wall.set"
    readonly property string kuwaiWall: Paths.stateHome + "/kuwai/wallpaper"

    // A small text file, read now: present from the first frame, no process.
    FileView { id: marker; path: root.lib + "/globalcontrol.sh"; blockLoading: true; printErrors: false }
    readonly property bool present: marker.loaded

    property bool hasShell: false
    property string wallpaper: ""
    // What's there, once at start; refresh() after something may have changed it
    // (the Themes panel calls it when it opens).
    function refresh() { probe.running = true; }
    Process {
        id: probe
        running: true
        // Arguments, not pasted into the script: the path is the user's.
        command: ["sh", "-c", 'command -v hyde-shell >/dev/null && echo shell; [ -e "$1" ] && echo wall; [ -e "$2" ] && echo kuwai', "sh", root.wallSet, root.kuwaiWall]
        stdout: StdioCollector {
            onStreamFinished: {
                const got = text.split("\n");
                root.hasShell = got.indexOf("shell") >= 0;
                root.wallpaper = got.indexOf("kuwai") >= 0 ? root.kuwaiWall : got.indexOf("wall") >= 0 ? root.wallSet : "";
            }
        }
    }

    property var said: ({})
    function run(args, what) {
        if (hasShell) { Quickshell.execDetached(["hyde-shell"].concat(args)); return true; }
        missing(what);
        return false;
    }
    // Once a session per feature: what needed HyDE, in a notification.
    function missing(what) {
        if (said[what]) return;
        said = Object.assign({}, said, { [what]: true });
        Quickshell.execDetached(["notify-send", "-a", "kuwai", "-i", "dialog-information", what + " needs HyDE",
                                 "HyDE (hyde-shell) isn't installed, so this does nothing here. kuwai works without it."]);
    }
}
