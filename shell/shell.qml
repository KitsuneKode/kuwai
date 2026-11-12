//@ pragma UseQApplication
// The rice: one Quickshell process for every desktop surface.
//
//   bin/rice-shell        start it (takes over notifications from dunst)
//   bin/rice …            control it (notifs …, center, reload, logs)
//
// Layout: config/ design tokens · components/ shared visuals ·
// services/ data and state (singletons) · modules/ the surfaces.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.osd
import qs.modules.notifications
import qs.modules.clipboard
import qs.modules.island
import qs.modules.lock
import qs.modules.overview
import qs.modules.voxtype
import qs.modules.assistant
import qs.modules.wallpaper
import qs.modules.screensaver
import qs.modules
import qs.services

ShellRoot {
    // Idle (dim, lock, screens off, sleep) lives in services/Idle: wake it up.
    readonly property bool idleOwned: Idle.enabled
    // Reminders fire from the shell, so they load with it (not on first use).
    readonly property int remindersKept: Reminders.items.length
    readonly property int alarmsKept: Alarms.items.length
    // Usage limits too: connected from the start (push-based, cheap).
    readonly property bool limitsAlive: Limits.alive
    readonly property var crashWatcher: Crashes
    readonly property var wellbeing: Wellbeing   // breaks and bedtime (services/Wellbeing)
    readonly property var memDiary: MemLog       // ~/.local/state/rice/memlog.tsv every 10 min
    // The stable copy (~/.local/share/kuwai) doesn't hot-reload: each reload
    // left ~25–30 MB behind, and `rice promote` restarts it cleanly anyway.
    // The dev tree keeps live reload for editing.
    // And after a crash Quickshell re-execs in place (same PID): the run
    // before it left its helpers running as our children. Stop those once.
    Component.onCompleted: {
        Quickshell.watchFiles = !Quickshell.shellDir.includes("/.local/share/kuwai/");
        reaper.running = true;
    }
    Process {
        id: reaper
        command: [Paths.bin + "/rice-reap"]
        stdout: SplitParser { onRead: line => console.log(line) }
    }
    Osd {}
    Popups {}
    Center {}
    ClipboardPanel {}
    IslandBar {}
    Lock { id: lockMod }
    Binding { target: MemLog; property: "locked"; value: lockMod.locked }
    GoodbyeOverlay {}
    LiveWallpaper {}
    Screensaver {}
    Blank {}
    Overview {}
    VoxtypeHost {}
    AssistantOverlay {}
    Shortcuts {}
    TestHook {}
}
