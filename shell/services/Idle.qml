pragma Singleton

// Idle: dim, fade, lock, screens off and sleep, owned by the shell (it was
// hypridle). Timings differ on the charger and on battery (Settings.idle*);
// Caffeine holds everything; a video app's own inhibitor (Wayland idle
// inhibit) is respected; while music plays the machine never sleeps on its
// own (it still locks: you walked away).
//
//   on charger   dim 3:00 · saver 3:00 · fade 4:45 · lock 5:00 · screens off 5:30
//   on battery   dim 2:00 · saver 2:30 · fade 2:45 · lock 3:00 · screens off 3:30 · sleep 15:00
//
// Before any sleep (lid, power menu, `systemctl suspend`) the screen locks
// first: a logind "delay" inhibitor is held and let go only once the lock is
// confirmed. `loginctl lock-session` locks too. If the shell can't run,
// kuwai-shell starts hypridle as the fallback (bin/kuwai-shell: broken()).
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs.config
import "idleLadder.mjs" as Ladder

Singleton {
    id: root

    // Preference is not readiness. Keep protection until the replacement acknowledges.
    property string confirmedOwner: "shell"
    property string ownerError: ""
    property string attemptOwner: ""
    readonly property bool enabled: root.confirmedOwner !== "hypridle"
    function reconcileOwner() {
        if (Settings.idleOwner !== "hypridle") root.confirmedOwner = "shell";
        if (ownerCommand.running || ownerCheck.running) return;
        root.attemptOwner = Settings.idleOwner === "hypridle" ? "hypridle" : "shell";
        ownerCommand.command = ["timeout", "10", "systemctl", "--user", root.attemptOwner === "hypridle" ? "start" : "stop", "hypridle.service"];
        ownerCommand.running = true;
    }
    function ownerStarted(code) {
        if (root.attemptOwner !== (Settings.idleOwner === "hypridle" ? "hypridle" : "shell")) { reconcileOwner(); return; }
        if (code !== 0) {
            root.ownerError = "Idle handoff failed; shell protection remains active. Retry or check hypridle.service.";
            root.confirmedOwner = "shell";
            return;
        }
        if (root.attemptOwner === "hypridle") ownerCheck.running = true;
        else root.ownerError = "";
    }
    function ownerChecked(code) {
        if (Settings.idleOwner !== "hypridle") { root.confirmedOwner = "shell"; reconcileOwner(); return; }
        if (code === 0) { root.confirmedOwner = "hypridle"; root.ownerError = ""; }
        else { root.confirmedOwner = "shell"; root.ownerError = "hypridle is unavailable; shell protection is active. Retry or check its service."; }
    }
    Process { id: ownerCommand; onExited: (code, status) => root.ownerStarted(code) }
    Process {
        id: ownerCheck
        command: ["timeout", "10", "systemctl", "--user", "is-active", "--quiet", "hypridle.service"]
        onExited: (code, status) => root.ownerChecked(code)
    }
    Connections { target: Settings; function onIdleOwnerChanged() { root.reconcileOwner(); } }
    Component.onCompleted: Qt.callLater(root.reconcileOwner)
    Timer {
        interval: 5000; repeat: true; running: Settings.idleOwner === "hypridle"
        onTriggered: {
            if (ownerCommand.running || ownerCheck.running) return;
            if (root.confirmedOwner === "hypridle") ownerCheck.running = true;
            else root.reconcileOwner();
        }
    }
    readonly property bool battery: UPower.onBattery
    // Seconds; 0 turns a step off.
    readonly property int dimAfter: battery ? Settings.idleDimBattery : Settings.idleDimAc
    readonly property int lockAfter: battery ? Settings.idleLockBattery : Settings.idleLockAc
    readonly property int offAfter: battery ? Settings.idleOffBattery : Settings.idleOffAc
    readonly property int sleepAfter: battery ? Settings.idleSleepBattery : Settings.idleSleepAc
    readonly property bool saverAllowed: Ladder.saverAllowed(Settings.screensaverWhen, Caffeine.on)
    readonly property int saverAfter: Ladder.saverAfter(Settings.screensaverMins, lockAfter, Caffeine.on || !enabled)
    readonly property string saverAfterText: Ladder.afterText(saverAfter)
    // Caffeine, or you're dictating: talking to voxtype is no key or pointer
    // input, and the screen dimmed and locked mid-sentence. (voxtype's own
    // systemd-inhibit only spoke to hypridle; these monitors don't read it.)
    readonly property bool held: Caffeine.on || Activities.voxBusy || appHeld
    property var appHolds: []
    readonly property bool appHeld: appHolds.length > 0
    Process {
        id: inhibitBridge
        running: true
        command: ["setpriv", "--pdeathsig", "KILL", "--", Paths.bin + "/kuwai-inhibit"]
        stdout: SplitParser {
            onRead: line => {
                let v = null;
                try { v = JSON.parse(line); } catch (e) { return; }
                if (Array.isArray(v)) root.appHolds = v;
            }
        }
        onExited: code => { root.appHolds = []; if (code !== 3 && code !== 4) bridgeAgain.start(); }
    }
    Timer { id: bridgeAgain; interval: 30000; onTriggered: inhibitBridge.running = true }
    readonly property string kuwai: Paths.bin + "/kuwai"

    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }

    // ── Dim: every screen (services/Dim: the panel to 1, a monitor to 0),
    // the keyboard light off
    IdleMonitor {
        enabled: root.enabled && !root.held && root.dimAfter > 0
        timeout: root.dimAfter
        respectInhibitors: true
        property bool down: false
        onIsIdleChanged: {
            if (isIdle && enabled) { down = true; Dim.down(); root.run("brightnessctl -sqd rgb:kbd_backlight set 0 2>/dev/null"); }
            else if (down) { down = false; Dim.up(); root.run("brightnessctl -qrd rgb:kbd_backlight 2>/dev/null"); }
        }
        onEnabledChanged: if (!enabled && down) { down = false; Dim.up(); root.run("brightnessctl -qrd rgb:kbd_backlight 2>/dev/null"); }
    }
    // ── Fade, 15 s before the lock: any input cancels it (modules/lock)
    IdleMonitor {
        enabled: root.enabled && !root.held && root.lockAfter > 20
        timeout: root.lockAfter - Ladder.fadeLead
        respectInhibitors: true
        property bool fading: false
        onIsIdleChanged: {
            if (isIdle && enabled) { fading = true; Quickshell.execDetached([root.kuwai, "fade", "start"]); }
            else if (fading) { fading = false; Quickshell.execDetached([root.kuwai, "fade", "stop"]); }
        }
        onEnabledChanged: if (!enabled && fading) { fading = false; Quickshell.execDetached([root.kuwai, "fade", "stop"]); }
    }
    // ── Lock
    IdleMonitor {
        enabled: root.enabled && !root.held && root.lockAfter > 0
        timeout: root.lockAfter
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) Quickshell.execDetached([root.kuwai, "lock"])
    }
    // ── Screens off. Not while work runs on power (Settings.idleScreensWhileWork,
    // Caffeine.workNow): dim and lock still happen, the screens stay on, and
    // they go off once the work ends if you're still away. (Holding the
    // monitor off instead would wake the screens whenever an agent started.)
    readonly property bool screensHeld: Settings.idleScreensWhileWork && Caffeine.workNow.length > 0
    function screens(off) {
        Saver.screensOff = off;
        root.run(`hyprctl dispatch 'hl.dsp.dpms({ action = "${off ? "disable" : "enable"}" })'`);
    }
    IdleMonitor {
        id: offMonitor
        enabled: root.enabled && !root.held && root.offAfter > 0
        timeout: root.offAfter
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle && root.screensHeld) return;
            if (isIdle || Saver.screensOff) root.screens(isIdle);
        }
        // Disabled while held (Caffeine, a dictation): the screens come back.
        // Clearing the flag is not DPMS. A click in the shell is not a key,
        // so key_press_enables_dpms does not run for it.
        onEnabledChanged: if (!enabled && Saver.screensOff) root.screens(false)
    }
    onScreensHeldChanged: if (!screensHeld && offMonitor.enabled && offMonitor.isIdle && !Saver.screensOff) screens(true)
    // ── Sleep (never while music plays, nor while work runs: Caffeine.working)
    IdleMonitor {
        id: sleepIdle
        enabled: root.enabled && !root.held && !Caffeine.working && root.sleepAfter > 0
        timeout: root.sleepAfter
        respectInhibitors: true
        onIsIdleChanged: root.sleepIfIdle()
    }
    function sleepIfIdle() {
        if (sleepIdle.enabled && sleepIdle.isIdle && !(Settings.idleNoSleepWhilePlaying && Media.playing))
            Quickshell.execDetached(["sh", "-c", '"$1" lock --wait && exec systemctl suspend', "sh", root.kuwai]);
    }
    Connections { target: Media; function onPlayingChanged() { if (Media.playing) afterMusic.stop(); else afterMusic.restart(); } }
    Timer { id: afterMusic; interval: 10000; onTriggered: root.sleepIfIdle() }
    onEnabledChanged: { sleepGuard.running = enabled; lockSignal.running = enabled; }

    // ── Lock before every sleep, and on `loginctl lock-session` ─────────
    // kuwai-sleepguard holds a logind "delay" inhibitor for the whole session:
    // on PrepareForSleep it locks, letting go only once the lock is confirmed
    // (or logind's own deadline is near), and takes it again on waking.
    Process {
        id: sleepGuard
        Component.onCompleted: running = root.enabled
        command: ["setpriv", "--pdeathsig", "KILL", "--", Paths.bin + "/kuwai-sleepguard", root.kuwai]
        onExited: if (root.enabled) rearm.restart()
    }
    Timer { id: rearm; interval: 500; onTriggered: if (root.enabled) sleepGuard.running = true }
    Process {
        id: lockSignal
        Component.onCompleted: running = root.enabled
        command: ["setpriv", "--pdeathsig", "KILL", "--", "sh", "-c", 'setpriv --pdeathsig KILL -- gdbus monitor --system --dest org.freedesktop.login1 | grep --line-buffered -E "Session\\.Lock \\(\\)"']
        stdout: SplitParser { onRead: Quickshell.execDetached([root.kuwai, "lock"]) }
        onExited: if (root.enabled) relisten.restart()
    }
    Timer { id: relisten; interval: 3000; onTriggered: if (root.enabled) lockSignal.running = true }
}
