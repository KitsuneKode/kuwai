pragma Singleton

// Dim: every screen down while you're away, back to exactly where it was when
// you return. One place for it: the idle dim (Idle, Caffeine off) and the
// screensaver's ten-minute dim (Caffeine on) both call down()/up().
//
// Down is 40 % of where you had it, at most 15 % (100 → 15, 30 → 12, 10 → 4):
// a flat 15 % did nothing at night, when you already sit at 15 or below. It
// goes through bin/rice-brightness, so external monitors (DDC) dim too
// and the brightness controller keeps knowing the real level (brightnessctl
// behind its back left the laptop panel only, and the controller stale).
//
// Up sets each screen back, reads it again 3 s later and sets what didn't
// take (a DDC write can be dropped), twice at most. The levels are written
// to a file first, so a shell restart while dimmed restores them on start.
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    readonly property string ctl: Paths.bin + "/rice-brightness"
    readonly property string file: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice/saver-dim.json"
    readonly property int most: 15
    function of(v) { return Math.max(1, Math.min(most, Math.round(v * 0.4))); }

    property bool dimmed: false
    property bool wanted: false          // down() asked, up() not yet
    // The levels before dimming, in memory: FileView doesn't hand back what
    // setText() just wrote (text() stayed empty), so wake restored nothing.
    // The file is only for a restart while dimmed.
    property var was: null

    function down() {
        if (wanted) return;
        wanted = true;
        reading.running = true;
    }
    function up() {
        wanted = false;
        let w = was;
        if (!w) try { w = JSON.parse(saved.text() || "null"); } catch (e) {}
        was = null;
        dimmed = false;
        if (!w) return;
        for (const name in w) set(name, w[name]);
        Quickshell.execDetached(["rm", "-f", file]);
        check.want = w;
        check.tries = 0;
        checkLater.restart();
    }
    function set(name, v) { Quickshell.execDetached([ctl, "--output", name, "set", String(v)]); }

    Process {
        id: reading
        command: [root.ctl, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let st = null;
                try { st = JSON.parse(text); } catch (e) { return; }
                if (!root.wanted || root.dimmed || !st || !st.outputs) return;   // back already
                const w = {};
                for (const name in st.outputs) {
                    const v = st.outputs[name].value;
                    if (typeof v === "number" && root.of(v) < v) w[name] = v;
                }
                if (!Object.keys(w).length) return;
                root.was = w;
                saved.setText(JSON.stringify(w));
                root.dimmed = true;
                for (const name in w) root.set(name, root.of(w[name]));
            }
        }
    }
    FileView { id: saved; path: root.file; printErrors: false; blockLoading: true }

    // Did it take? Read back, set again what didn't (twice at most).
    Timer { id: checkLater; interval: 3000; onTriggered: check.running = true }
    Process {
        id: check
        property var want: null
        property int tries: 0
        command: [root.ctl, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const want = check.want;
                let st = null;
                try { st = JSON.parse(text); } catch (e) {}
                if (!want || root.dimmed) return;
                let off = 0;
                for (const name in want) {
                    const o = st && st.outputs && st.outputs[name];
                    if (!o) continue;
                    if (o.pending !== null && o.pending !== undefined) off++;   // still writing: look again
                    else if (o.value !== want[name]) { off++; root.set(name, want[name]); }
                }
                if (off && ++check.tries < 2) checkLater.restart();
                else check.want = null;
            }
        }
    }

    // Dimmed when the last shell went: put it back.
    Component.onCompleted: if (saved.text() !== "") up()
}
