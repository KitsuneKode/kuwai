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
import qs.modules

ShellRoot {
    Osd {}
    Popups {}
    Center {}
    ClipboardPanel {}
    IslandBar {}
    Lock {}
    Overview {}
    VoxtypeHost {}
    Shortcuts {}
}
