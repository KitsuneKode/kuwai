pragma Singleton

// The screensaver's state, for whoever shouldn't waste work under it (the
// live wallpaper pauses: nobody can see it, and the same file would be
// decoded twice). (No braces before the pragma: Quickshell's scanner stops.)

import QtQuick
import Quickshell

Singleton {
    property bool showing: false
}
