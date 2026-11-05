// Test hook (docs/ROADMAP.md, Phase 1): put the island and its services in
// any state without the hardware or the event, for screenshots and checks.
//
//   qs ipc -p <shell> call test moment   KIND LABEL VALUE   (a moment for 4 s)
//   qs ipc -p <shell> call test alert    warn|crit TITLE    (a warning, until clear)
//   qs ipc -p <shell> call test agents   N WAITING          (N agents working, WAITING of them waiting)
//   qs ipc -p <shell> call test timer    SECONDS LABEL
//   qs ipc -p <shell> call test clear                       (back to the real state)
// (Notification bursts: bin/rice-fixture, through the real D-Bus path.)
//
// Same reach as every other `qs ipc` call: your own user only.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.services

Scope {
    id: hook
    property bool testing: false
    property var realFeed: null
    IpcHandler {
        target: "test"
        function moment(kind: string, label: string, value: string): void {
            const tone = { focus: "#bf5af2", battery: Theme.red, timer: Theme.green, agent: Theme.orange }[kind] || Theme.textPrimary;
            Moments.show({ kind: kind, glyph: "\u{f02cb}", label: label, value: value, ring: -1, tone: tone }, 4000);
        }
        function alert(level: string, title: string): void {
            Alerts.active = [{ id: "test", level: level === "crit" ? "crit" : "warn", glyph: "\u{f050f}", title: title, detail: "test" }];
        }
        function agents(n: int, waiting: int): void {
            // The agents.json shape (kittymux plan 014); the real feed comes back on clear.
            if (!hook.testing) { hook.realFeed = Kittymux.feed; hook.testing = true; }
            const names = ["claude", "codex", "agy", "opencode", "gemini"];
            const list = [];
            for (let i = 0; i < n; i++) {
                const name = names[i % names.length];
                list.push({ key: "test" + i, agent: name, brand: name, title: "Test task " + (i + 1),
                            tab_title: "test", cwd: "~/Projects/test", state: i < waiting ? "waiting" : "working" });
            }
            Kittymux.feed = { version: 1, agents: list };
        }
        function timer(seconds: int, label: string): void { Timers.start(seconds, label); }
        function clear(): void {
            Alerts.active = [];
            Moments.now = null;
            if (hook.testing) { Kittymux.feed = hook.realFeed; hook.testing = false; }
            for (const t of Timers.timers.slice()) if (/^test/i.test(t.label)) Timers.cancel(t.id);
        }
    }
}
