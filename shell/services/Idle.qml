pragma Singleton

// Idle: dim, fade, lock, screens off and sleep, owned by the shell (it was
// hypridle). Timings differ on the charger and on battery (Settings.idle*);
// Caffeine holds everything; a video app's own inhibitor (Wayland idle
// inhibit) is respected; while music plays the machine never sleeps on its
// own (it still locks: you walked away).
//
//   on charger   dim 4:00 · fade 4:45 · lock 5:00 · screens off 5:30 · sleep never
//   on battery   dim 2:00 · fade 2:45 · lock 3:00 · screens off 3:30 · sleep 15:00
//
// Before any sleep (lid, power menu, `systemctl suspend`) the screen locks
// first: a logind "delay" inhibitor is held and let go only once the lock is
// confirmed. `loginctl lock-session` locks too. If the shell can't run,
// rice-shell starts hypridle as the fallback (bin/rice-shell: broken()).
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs.config

Singleton {
    id: root

    readonly property bool enabled: Settings.idleOwner !== "hypridle"
    readonly property bool battery: UPower.onBattery
    // Seconds; 0 turns a step off.
    readonly property int dimAfter: battery ? Settings.idleDimBattery : Settings.idleDimAc
    readonly property int lockAfter: battery ? Settings.idleLockBattery : Settings.idleLockAc
    readonly property int offAfter: battery ? Settings.idleOffBattery : Settings.idleOffAc
    readonly property int sleepAfter: battery ? Settings.idleSleepBattery : Settings.idleSleepAc
    readonly property bool held: Caffeine.on
    readonly property string rice: Paths.bin + "/rice"

    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }

    // ── Dim: every screen (services/Dim: 40 %, at most 15 %, monitors too),
    // the keyboard light off
    IdleMonitor {
        enabled: root.enabled && !root.held && root.dimAfter > 0
        timeout: root.dimAfter
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle) { Dim.down(); root.run("brightnessctl -sqd rgb:kbd_backlight set 0 2>/dev/null"); }
            else { Dim.up(); root.run("brightnessctl -qrd rgb:kbd_backlight 2>/dev/null"); }
        }
    }
    // ── Fade, 15 s before the lock: any input cancels it (modules/lock)
    IdleMonitor {
        enabled: root.enabled && !root.held && root.lockAfter > 20
        timeout: root.lockAfter - 15
        respectInhibitors: true
        onIsIdleChanged: Quickshell.execDetached([root.rice, "fade", isIdle ? "start" : "stop"])
    }
    // ── Lock
    IdleMonitor {
        enabled: root.enabled && !root.held && root.lockAfter > 0
        timeout: root.lockAfter
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) Quickshell.execDetached([root.rice, "lock"])
    }
    // ── Screens off
    IdleMonitor {
        enabled: root.enabled && !root.held && root.offAfter > 0
        timeout: root.offAfter
        respectInhibitors: true
        onIsIdleChanged: root.run(`hyprctl dispatch 'hl.dsp.dpms({ action = "${isIdle ? "disable" : "enable"}" })'`)
    }
    // ── Sleep (never while music plays)
    IdleMonitor {
        enabled: root.enabled && !root.held && root.sleepAfter > 0
        timeout: root.sleepAfter
        respectInhibitors: true
        onIsIdleChanged: if (isIdle && !(Settings.idleNoSleepWhilePlaying && Media.playing)) Quickshell.execDetached(["systemctl", "suspend"])
    }

    // ── Lock before every sleep, and on `loginctl lock-session` ─────────
    // A delay inhibitor: logind waits (up to InhibitDelayMaxSec) while we
    // lock; the process ends once the lock is confirmed, which lets the sleep
    // go on. After waking it starts again for the next sleep.
    Process {
        id: sleepGuard
        running: root.enabled
        // setpriv --pdeathsig: these die with the shell, even a kill -9 (a
        // left-over guard would delay every sleep; a listener, lock twice).
        command: ["setpriv", "--pdeathsig", "KILL", "--", "systemd-inhibit", "--what=sleep", "--mode=delay", "--who=rice", "--why=Lock the screen before sleeping",
                  "setpriv", "--pdeathsig", "KILL", "--", "sh", "-c", 'setpriv --pdeathsig KILL -- gdbus monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 | while read -r l; do case $l in *PrepareForSleep*true*) "$1" lock --wait; exit 0;; esac; done', "sh", root.rice]
        onExited: if (root.enabled) rearm.restart()
    }
    // Soon after waking (a lid closed again right away is still locked first);
    // not instantly, so a guard that fails at once can't spin.
    Timer { id: rearm; interval: 500; onTriggered: if (root.enabled) sleepGuard.running = true }
    Process {
        id: lockSignal
        running: root.enabled
        command: ["setpriv", "--pdeathsig", "KILL", "--", "sh", "-c", 'setpriv --pdeathsig KILL -- gdbus monitor --system --dest org.freedesktop.login1 | grep --line-buffered -E "Session\\.Lock \\(\\)"']
        stdout: SplitParser { onRead: Quickshell.execDetached([root.rice, "lock"]) }
        onExited: if (root.enabled) relisten.restart()
    }
    Timer { id: relisten; interval: 3000; onTriggered: if (root.enabled) lockSignal.running = true }
}
