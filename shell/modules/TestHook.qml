// Test hook (docs/ROADMAP.md, Phase 1): put the island and its services in
// any state without the hardware or the event, for screenshots and checks.
//
//   qs ipc -p <shell> call test moment   KIND LABEL VALUE   (a moment for 4 s)
//   qs ipc -p <shell> call test alert    warn|crit TITLE    (a warning, until clear)
//   qs ipc -p <shell> call test agents   N WAITING          (N agents working, WAITING of them waiting)
//   qs ipc -p <shell> call test timer    SECONDS LABEL
//   qs ipc -p <shell> call test card     alarm|reminder|timer TITLE   (the island's card, silent)
//   qs ipc -p <shell> call test clear                       (back to the real state)
//   qs ipc -p <shell> call test collect                     (run the JS garbage collector)
//   qs ipc -p <shell> call test gallery  [on|off]           (the design system on one sheet; no keyboard)
//   qs ipc -p <shell> call test settings N                  (the Settings panel on page N, no keyboard; -1 closes)
//   qs ipc -p <shell> call test compile  modules/x/Y.qml    (compiles it, makes nothing: "ok" or the error)
//   qs ipc -p <shell> call test peek     SCREEN short|long [expanded]   (a sample notification in that
//                                                          screen's notch; no pointer, no keyboard, no D-Bus)
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
    LazyLoader { id: galleryLoader; active: false; Gallery {} }
    property int settingsPage: 0
    property string settingsQuery: ""
    LazyLoader { id: settingsLoader; active: false; SettingsPreview { page: hook.settingsPage; query: hook.settingsQuery } }
    IpcHandler {
        target: "test"
        function moment(kind: string, label: string, value: string): void {
            const tone = { focus: Theme.focus, battery: Theme.red, timer: Theme.green, agent: Theme.orange }[kind] || Theme.textPrimary;
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
        // Panels load on first open, so a broken one hides until then; this
        // compiles a file (types, imports, syntax) without creating it.
        function compile(file: string): string {
            const c = Qt.createComponent(Quickshell.shellDir + "/" + file, Component.PreferSynchronous);
            const r = c.status === Component.Ready ? "ok" : c.status === Component.Error ? c.errorString() : "status " + c.status;
            c.destroy();
            return r;
        }
        function gallery(state: string): void { galleryLoader.active = state !== "off"; }
        function settings(page: int): void { hook.settingsPage = page; settingsLoader.active = page >= 0; }
        // The same, with words in its search: `test settingsSearch "hover delay"`.
        function settingsSearch(q: string): void { hook.settingsQuery = q; settingsLoader.active = true; }
        // An alarm / reminder / timer card (AlarmCard), silent; its buttons only close it.
        function card(kind: string, title: string): void {
            const sub = { alarm: "07:30 · Alarm", reminder: "Reminder · now", timer: "Timer · 10 min done" }[kind] || "";
            const act = kind === "alarm" ? { secondary: ["Snooze", () => {}], primary: ["Stop", () => {}] }
                      : kind === "reminder" ? { secondary: ["Later", () => {}], primary: ["Done", () => {}] }
                      : { secondary: ["Repeat", () => {}], primary: ["Done", () => {}] };
            Moments.showCard({ key: "test-" + kind, kind: kind, id: Date.now(), title: title, sub: sub, act: act }, 12000);
        }
        function timer(seconds: int, label: string): void { Timers.start(seconds, label); }
        // Memory: run the JS garbage collector now (for measuring what it frees).
        function collect(): void { gc(); }
        function peek(screen: string, size: string, expanded: string): void {
            const long = size === "long";
            const body = long
                ? "Summary by CodeRabbit\n\n• New Features\n  • An optional pixel tab bar for vertical layouts, with project-grouped tabs, status, hover highlights and close controls.\n  • Groups fold and expand; the bar scrolls when tabs don't fit.\n  • Busy tabs ask before closing.\n\n• Documentation\n  • Setup and customisation for the pixel bar.\n  • HiDPI, glass and several kitty windows.\n  • One more line, so it runs past the cap and scrolls."
                : "Your build finished in 3 m 12 s. 1,801 tests passed.";
            Notifs.peekHeld = true;
            Notifs.peek = { app: "Test", status: "Mentioned you", title: long ? "Pixel tab bar (opt-in): the bar drawn as a picture, Rex-style" : "Build finished",
                            body: body, full: long ? body : "", time: Date.now(), test: true, actions: [] };
            Notifs.peekOn = screen;
            if (expanded === "expanded") Notifs.expandPeek();
        }
        function clear(): void {
            Alerts.active = [];
            if (Notifs.peek && Notifs.peek.test) { Notifs.peekHeld = false; Notifs.peek = null; }
            Moments.now = null;
            if (Moments.card && String(Moments.card.key).indexOf("test-") === 0) Moments.dropCard();
            if (hook.testing) { Kittymux.feed = hook.realFeed; hook.testing = false; }
            for (const t of Timers.timers.slice()) if (/^test/i.test(t.label)) Timers.cancel(t.id);
        }
    }
}
