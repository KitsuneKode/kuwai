//@ pragma UseQApplication
// The rice: one Quickshell process for every desktop surface.
//
//   bin/rice-shell        start it (takes over notifications from dunst)
//   bin/rice …            control it (notifs …, center, reload, logs)
//
// Layout: config/ design tokens · components/ shared visuals ·
// services/ data and state (singletons) · modules/ the surfaces.
import Quickshell
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
    Osd {}
    Popups {}
    Center {}
    ClipboardPanel {}
    IslandBar {}
    Lock {}
    GoodbyeOverlay {}
    LiveWallpaper {}
    Screensaver {}
    Overview {}
    VoxtypeHost {}
    AssistantOverlay {}
    Shortcuts {}
    TestHook {}
}
