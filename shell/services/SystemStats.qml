pragma Singleton

// CPU (per core), memory, temperatures, fans, the NVIDIA GPU and pending
// updates: what Waybar's cpu/memory/gpuinfo/sensorsinfo/updates showed.
// One small shell loop reads it every two seconds, and only while something
// on screen shows it (`watch()` / `unwatch()`), so an idle island costs
// nothing. The GPU is read only while it is awake: nvidia-smi on a suspended
// laptop GPU would wake it up (and keep it up).
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int watchers: 0
    function watch() { watchers++; }
    function unwatch() { watchers = Math.max(0, watchers - 1); }

    property real cpu: 0                 // 0–1, all cores
    property var cores: []               // 0–1 each
    property real memUsed: 0             // bytes
    property real memTotal: 0
    readonly property real mem: memTotal ? memUsed / memTotal : 0
    property real swapUsed: 0
    property int cpuTemp: 0              // °C
    property int gpuTemp: 0
    property var fans: []                // rpm
    property string gpuState: ""         // active | suspended | "" (no NVIDIA GPU)
    property real gpu: 0                 // 0–1
    property real gpuMemUsed: 0          // MiB
    property real gpuMemTotal: 0
    property real gpuPower: 0            // W
    property string load: ""
    property var coreMHz: []             // current frequency per thread
    property var pThreads: []            // thread numbers on performance cores (the rest are efficiency cores)
    property int igpuMHz: 0              // Intel GPU: current and top frequency (it has no busy %)
    property int igpuMax: 0
    function coreKind(i) { return pThreads.length ? (pThreads.includes(i) ? "Performance core" : "Efficiency core") : "Core"; }
    function ranges(text) { const out = []; for (const part of text.split(",")) { const [a, b] = part.split("-").map(Number); for (let i = a; i <= (isNaN(b) ? a : b); i++) out.push(i); } return out; }
    readonly property int updates: Updates.total   // pending updates (-1: not checked yet); services/Updates owns them
    property bool ready: false

    property var prev: ({})              // cpu name -> [busy, total]
    property var frame: []

    function commit(lines) {
        const next = {};
        const cores = [];
        for (const l of lines) {
            const f = l.trim().split(/\s+/);
            if (/^cpu\d*$/.test(f[0])) {
                const v = f.slice(1).map(Number);
                const idle = v[3] + (v[4] || 0), total = v.reduce((a, b) => a + b, 0);
                const p = prev[f[0]];
                // The first frame has nothing to compare with: since boot.
                const use = p && total > p[1] ? 1 - (idle - p[0]) / (total - p[1]) : total ? 1 - idle / total : 0;
                next[f[0]] = [idle, total];
                if (f[0] === "cpu") cpu = Math.max(0, Math.min(1, use));
                else cores.push(Math.max(0, Math.min(1, use)));
            } else if (f[0] === "MemTotal:") memTotal = Number(f[1]) * 1024;
            else if (f[0] === "MemAvailable:") memUsed = memTotal - Number(f[1]) * 1024;
            else if (f[0] === "SwapTotal:") root._swapTotal = Number(f[1]) * 1024;
            else if (f[0] === "SwapFree:") swapUsed = root._swapTotal - Number(f[1]) * 1024;
            else if (f[0] === "temps") {
                cpuTemp = Math.round(Number(f[1] || 0) / 1000);
                gpuTemp = Math.round(Number(f[2] || 0) / 1000);
                fans = f.slice(3).map(Number).filter(n => !isNaN(n));
            } else if (f[0] === "gpustate") gpuState = f[1] || "";
            else if (f[0] === "gpu") {
                const g = l.slice(4).split(",").map(s => Number(s.trim()));
                gpu = (g[0] || 0) / 100; gpuMemUsed = g[1] || 0; gpuMemTotal = g[2] || 0; gpuPower = g[3] || 0;
            } else if (f[0] === "load") load = f.slice(1).join(" ");
            else if (f[0] === "freq") coreMHz = f.slice(1).map(n => Math.round(Number(n) / 1000));
            else if (f[0] === "kinds" && f[1]) pThreads = ranges(f[1]);
            else if (f[0] === "igpu") { igpuMHz = Number(f[1]) || 0; igpuMax = Number(f[2]) || 0; }
        }
        if (gpuState !== "active") gpu = 0;
        // Each core's own idle/total were remembered under its name, so the
        // first frame reads 0 and every later one is the real share.
        prev = next;
        root.cores = cores;
        ready = true;
    }
    property real _swapTotal: 0

    Process {
        running: root.watchers > 0
        command: ["sh", "-c", `
            hw=; for h in /sys/class/hwmon/*; do [ "$(cat "$h/name" 2>/dev/null)" = legion_hwmon ] && hw=$h; done
            gs=; for d in /sys/bus/pci/drivers/nvidia/0000:*; do [ -e "$d/power/runtime_status" ] && gs=$d/power/runtime_status; done
            while :; do
                echo @
                grep '^cpu' /proc/stat
                grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo
                [ -n "$hw" ] && echo "temps $(cat "$hw/temp1_input" "$hw/temp2_input" "$hw"/fan*_input 2>/dev/null | tr '\\n' ' ')"
                if [ -n "$gs" ]; then
                    read -r st < "$gs"; echo "gpustate $st"
                    [ "$st" = active ] && echo "gpu $(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits 2>/dev/null | head -1)"
                fi
                read -r a b c _ < /proc/loadavg; echo "load $a $b $c"
                s=; i=0; while [ -e "/sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq" ]; do read -r v < "/sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq"; s="$s $v"; i=$((i+1)); done; echo "freq$s"
                [ -r /sys/devices/cpu_core/cpus ] && { read -r p < /sys/devices/cpu_core/cpus; echo "kinds $p"; }
                for c in /sys/class/drm/card[0-9]; do [ -r "$c/gt_act_freq_mhz" ] && { read -r x < "$c/gt_act_freq_mhz"; read -r y < "$c/gt_max_freq_mhz"; echo "igpu $x $y"; }; done
                echo '#'
                sleep 2
            done`]
        stdout: SplitParser {
            onRead: line => {
                if (line === "@") root.frame = [];
                else if (line === "#") root.commit(root.frame);
                else root.frame.push(line);
            }
        }
    }

    // Weather (what Waybar's weather module showed; HyDE's own script is
    // broken here): wttr.in for the location in HyDE's config, every 30 min.
    // From services/Weather (one fetch for the island and the lock screen;
    // this used to fetch wttr.in a second time, every 30 minutes).
    readonly property string weatherTemp: Weather.ok ? Weather.temp + "°" : ""
    readonly property string weatherText: Weather.ok ? Weather.desc : ""
    readonly property string weatherGlyph: {
        const t = weatherText.toLowerCase();
        if (/thunder/.test(t)) return "\u{f0593}";
        if (/snow|sleet|ice/.test(t)) return "\u{f0598}";
        if (/rain|drizzle|shower/.test(t)) return "\u{f0597}";
        if (/fog|mist|haze/.test(t)) return "\u{f0591}";
        if (/overcast|cloud/.test(t)) return /partly/.test(t) ? "\u{f0595}" : "\u{f0590}";
        return new Date().getHours() >= 18 || new Date().getHours() < 6 ? "\u{f0594}" : "\u{f0599}";
    }
    function bytes(n) {
        if (n >= 1073741824) return (n / 1073741824).toFixed(n >= 10737418240 ? 0 : 1) + " GB";
        return Math.round(n / 1048576) + " MB";
    }
}
