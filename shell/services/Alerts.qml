pragma Singleton

// Warnings worth interrupting for, shown by the island like a notification
// that grows out of it (then a coloured mark at rest until it clears):
// memory past 82 %, swap almost full, a disk past 92 %, the CPU above 95 °C
// for half a minute, the battery at 10 % and not charging. Every 10 s two
// small reads with no process (/proc/meminfo, the CPU sensor); the biggest
// app and the disks once a minute (ps, df), or at once when memory is high;
// nothing while locked or the screens are off. Each alert shows once when
// it starts or gets worse, not on every check.
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.config

Singleton {
    id: root

    property var active: []              // [{ id, level: "warn"|"crit", glyph, title, detail }]
    property var banner: null            // the one being shown big right now
    // The screen it came up on: it stays there while it shows (it jumped
    // to the other monitor mid-read when focus moved).
    property string bannerOn: ""
    onBannerChanged: bannerOn = banner ? Screens.focusedName : ""
    property var shown: ({})             // id -> level last announced
    property int hot: 0                  // consecutive hot CPU samples

    readonly property var battery: UPower.displayDevice
    readonly property bool batteryLow: battery && battery.isLaptopBattery && battery.isPresent && UPower.onBattery
        && (battery.percentage > 1 ? battery.percentage : battery.percentage * 100) <= 10

    property var last: ({})
    function commit(v) {
        const out = [];
        const memT = v.MemTotal || 1, memA = v.MemAvailable || memT;
        const mem = 1 - memA / memT;
        const gb = n => (n / 1048576).toFixed(1) + " GB";
        if (mem >= 0.82) out.push({ id: "mem", level: mem >= 0.92 ? "crit" : "warn", glyph: "\u{f035b}", title: "Memory at " + Math.round(mem * 100) + "%",
                                    detail: gb(memT - memA) + " of " + gb(memT) + " used" + (v.top ? " · most: " + v.top : "") });
        const swT = v.SwapTotal || 0, swF = v.SwapFree || 0;
        if (swT > 0 && 1 - swF / swT >= 0.9) out.push({ id: "swap", level: "warn", glyph: "\u{f04c4}", title: "Swap almost full", detail: gb(swT - swF) + " of " + gb(swT) + " in use" });
        // One app holding a fifth of memory or more (a runaway browser tab is the
        // usual one): say which, since "memory at 70 %" alone gives you nothing to do.
        if (v.hog && v.hog.kb >= memT * 0.2) out.push({ id: "hog:" + v.hog.name, level: "warn", glyph: "\u{f035b}",
            title: v.hog.name + " is holding " + gb(v.hog.kb),
            detail: (v.hog.tab ? "One browser tab: find it in about:processes and reload or close it" : "Quit or restart it to give the memory back") + " · " + Math.round(v.hog.kb / memT * 100) + "% of memory" });
        for (const d of v.disks || []) if (d.use >= 92) out.push({ id: "disk:" + d.mount, level: d.use >= 97 ? "crit" : "warn", glyph: "\u{f02ca}", title: "Disk " + d.mount + " at " + d.use + "%", detail: d.free + " free" });
        hot = (v.cpuTemp || 0) >= 95 ? hot + 1 : 0;
        if (hot >= 3) out.push({ id: "temp", level: "crit", glyph: "\u{f050f}", title: "CPU at " + v.cpuTemp + "°", detail: "Running hot for 30 seconds" });
        if (batteryLow) out.push({ id: "battery", level: "crit", glyph: "\u{f008e}", title: "Battery low", detail: "Plug in soon" });
        active = out;
        // Announce what's new or worse; forget what cleared.
        const now = {};
        for (const a of out) {
            now[a.id] = a.level;
            if (shown[a.id] !== a.level && !(shown[a.id] === "crit" && a.level === "warn")) { banner = a; bannerFor.restart(); }
        }
        shown = now;
    }
    // Folds away after 7 s — but never while the pointer is on it.
    property bool held: false
    onHeldChanged: if (held) bannerFor.stop(); else if (banner) bannerFor.restart()
    Timer { id: bannerFor; interval: 7000; onTriggered: if (!root.held) root.banner = null }

    // Updates: told once, when the session has settled (after the greeting
    // and the first look at what's connected) and the island is free; only
    // for versions not told before (remembered across restarts), at most
    // every 6 h (a nightly package moves daily). Then shown in System.
    readonly property var updateKeys: Updates.total > 0 ? Updates.repo.concat(Updates.aur).map(p => p.name + "@" + (p.new || "")).concat(Updates.flatpak.map(p => p.id + "@" + (p.new || p.version || ""))) : []
    FileView {
        id: told
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/kuwai/updates-told.json"
        blockLoading: true
        printErrors: false
    }
    function toldData() { try { return JSON.parse(told.text() || "{}"); } catch (e) { return {}; } }
    function tellUpdates() {
        const n = Updates.total;
        if (n <= 0 || !Settings.updatesAnnounce) return;
        if (!Moments.settled || Moments.now || Moments.card || banner) { tellLater.restart(); return; }
        const t = toldData();
        const seen = t.keys || [];
        const unseen = updateKeys.filter(k => seen.indexOf(k) < 0);
        if (!unseen.length) return;
        // Unseen versions are new by definition: tell them. Only space two
        // notes that would land within 45 min of each other (no nagging), and
        // never drop the set (an early return used to lose it for good).
        const wait = (t.at || 0) > 0 ? 45 * 60 * 1000 - (Date.now() - t.at) : 0;
        if (wait > 0) { tellLater.interval = wait; tellLater.restart(); return; }
        tellLater.interval = 4000;
        told.setText(JSON.stringify({ at: Date.now(), keys: updateKeys }) + "\n");
        banner = { id: "updates", level: "info", glyph: "\u{f06b0}", title: n + (n === 1 ? " update" : " updates") + " available", detail: "Review what changes, then update", panel: "updates", action: "Review" };
        bannerFor.restart();
    }
    Timer { id: tellLater; interval: 4000; onTriggered: root.tellUpdates() }
    Connections { target: Updates; function onTotalChanged() { root.tellUpdates(); } }
    Connections { target: Moments; function onSettledChanged() { root.tellUpdates(); } }
    function dismiss() { banner = null; }

    property int tick: 0
    property int cpuTemp: 0
    property string tempPath: ""         // the Legion's CPU sensor, if there is one
    Process {
        running: true
        command: ["sh", "-c", 'for h in /sys/class/hwmon/*; do [ "$(cat "$h/name" 2>/dev/null)" = legion_hwmon ] && echo "$h/temp1_input"; done']
        stdout: StdioCollector { onStreamFinished: root.tempPath = text.trim().split("\n")[0] || "" }
    }
    FileView { id: meminfo; path: "/proc/meminfo"; printErrors: false; onLoaded: root.sample(text()) }
    FileView { id: tempFile; path: root.tempPath; printErrors: false; onLoaded: root.cpuTemp = Math.round(Number(text().trim()) / 1000) }
    Timer {
        interval: 10000
        repeat: true
        triggeredOnStart: true
        running: !Saver.locked && !Saver.screensOff
        onTriggered: { if (root.tempPath) tempFile.reload(); meminfo.reload(); }
    }
    function sample(text) {
        const v = {};
        for (const l of text.split("\n")) {
            const m = /^(MemTotal|MemAvailable|SwapTotal|SwapFree):\s+(\d+)/.exec(l);
            if (m) v[m[1]] = Number(m[2]);
        }
        if (!v.MemTotal) return;
        v.cpuTemp = cpuTemp;
        v.disks = last.disks || [];
        v.hog = last.hog;
        v.top = last.top;
        const high = 1 - (v.MemAvailable || 0) / v.MemTotal >= 0.82;
        if ((tick % 6 === 0 || high) && !heavy.running) heavy.running = true;   // lands in `last` for the next sample
        tick++;
        commit(v);
    }
    // The biggest app (a runaway browser tab says so) and the disks.
    Process {
        id: heavy
        command: ["sh", "-c", `
            ps -eo rss=,args= --sort=-rss | head -1 | awk '{a=$2; t=0; if ($0 ~ /zen-bin -contentproc|firefox -contentproc|--type=renderer/) t=1; n=a; sub(/.*\\//, "", n); printf "hog %d %d %s\\n", $1, t, n}'
            ps -eo rss=,comm= --sort=-rss | head -1 | awk '{r=$1; $1=""; sub(/^ /, ""); printf "top %s %.1f GB\\n", $0, r/1048576}'
            df -P -B1 / /home 2>/dev/null | awk 'NR>1 && !seen[$1]++ {print "disk", $6, $5, $4}'`]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = { disks: [] };
                for (const line of text.split("\n")) {
                    const f = line.trim().split(/\s+/);
                    if (f[0] === "disk") {
                        const free = Number(f[3]);
                        out.disks.push({ mount: f[1], use: parseInt(f[2]), free: free >= 1073741824 ? Math.round(free / 1073741824) + " GB" : Math.round(free / 1048576) + " MB" });
                    } else if (f[0] === "hog") {
                        const bin = f.slice(3).join(" ");
                        const nm = /zen/.test(bin) ? "Zen" : /firefox/.test(bin) ? "Firefox" : /chrom/.test(bin) ? "Chrome" : /t3code/.test(bin) ? "T3 Code" : bin;
                        out.hog = { kb: Number(f[1]), tab: f[2] === "1", name: f[2] === "1" ? nm + " tab" : nm };
                    } else if (f[0] === "top") out.top = f[1] + " " + f.slice(2).join(" ");
                }
                root.last = out;
            }
        }
    }
}
