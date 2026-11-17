pragma Singleton

// The screensaver's state, for whoever shouldn't waste work under it (the
// live wallpaper pauses: nobody can see it, and the same file would be
// decoded twice). Also the lock and the screens being off (modules/lock,
// services/Idle): nobody is looking, so device cards and ambient moments
// keep quiet, and what changed is not replayed when you come back.
// (No braces before the pragma: Quickshell's scanner stops.)

import QtQuick
import Quickshell

Singleton {
    id: root
    property bool showing: false
    property bool locked: false
    property bool screensOff: false
    // Nobody is looking now, or you came back a moment ago: monitors waking
    // from power-off come back as new outputs (their audio too), Bluetooth
    // reconnects; none of that is news.
    readonly property bool away: locked || screensOff || settling.running
    onLockedChanged: if (!locked) settling.restart()
    onScreensOffChanged: if (!screensOff) settling.restart()
    Timer { id: settling; interval: 8000 }
}
