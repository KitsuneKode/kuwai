// The rice's notification server (org.freedesktop.Notifications). Replaces
// dunst while the rice runs; bin/rice-shell hands the bus name over, and if
// this process dies D-Bus activation brings dunst back as the fallback.
//
// History, do-not-disturb and what's been seen persist in
// ~/.local/state/rice/notifications.json. Control it with `bin/rice notifs …`
// and `bin/rice center` (IPC targets "notifs" and "center").
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications

Singleton {
    id: root

    property var items: []                    // newest first (NotifItem)
    // Critical ones ride at the top of the stack; otherwise newest first.
    readonly property var popups: {
        const shown = items.filter(i => i.popup);
        return [...shown.filter(i => i.severity === "critical"), ...shown.filter(i => i.severity !== "critical")];
    }
    property bool dnd: false
    // Toasts beyond the visible three wait (hidden) behind the stack, as in
    // Sonner; this only bounds how many can pile up.
    readonly property int maxPopups: 8
    readonly property int maxItems: 200

    // Set by the toast stack while it's expanded or being touched: every
    // toast's clock pauses (and resumes where it was).
    property bool held: false

    // A new toast was shown: the stack follows it to the focused monitor.
    signal arrived()

    // The front toast as Popups last laid it out ({ screen, height } or
    // null): where the center morphs out of when it opens over the stack.
    property var frontToast: null

    // Notification center
    property bool centerOpen: false
    property string centerTab: "notifications"     // notifications | agents | sound | controls
    property real closedAt: 0
    property string centerVia: "key"                // what opened/closed it: key | pointer
    property real lastSeen: 0
    readonly property int unread: items.filter(i => i.time > lastSeen).length

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/rice"
    property bool loaded: false

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        actionsSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        onNotification: n => root.receive(n)
    }

    function receive(n) {
        n.tracked = true;
        // Carried over by a hot reload (keepOnReload): it's already in the
        // history restored from disk, so reattach it there instead of adding
        // (and toasting) it twice.
        if (n.lastGeneration) {
            const known = items.find(i => !i.notification && i.nid === n.id);
            if (known) known.notification = n;
            return;
        }
        const a = NotifAdapters.adapt(n);
        if (a.silent) { n.dismiss(); return; }
        const twin = a.groupKey ? items.find(i => i.groupKey === a.groupKey && i.popup && !i.leaving) : null;
        if (twin) {
            twin.absorb(n, a);
            save();
            return;
        }
        const item = itemComp.createObject(root, { notification: n });
        item.apply(n, a);
        // While the center is open the new one just lands in its list.
        item.popup = !centerOpen && (!dnd || item.severity === "critical");
        items = [item, ...items];
        // Sound only where it earns its place: critical alerts (they also
        // break through do-not-disturb), unless the sender asked for silence.
        if (item.severity === "critical" && !(n.hints && n.hints["suppress-sound"])) alertSound.running = true;

        if (item.popup) arrived();
        // Too many on screen: the oldest steps out.
        const shown = popups.filter(i => !i.leaving);
        for (let k = maxPopups; k < shown.length; k++) shown[k].leaving = true;
        trim();
        save();
    }

    // ── Card interactions ────────────────────────────────────────────────
    // Click: run the app's default action (or its only one) and bring its
    // window forward.
    function activate(item) {
        const n = item.notification;
        const focusClass = item.focusClass;
        item.leaving = true;
        if (item.jump) { jumpTo(item); return; }
        if (n) {
            const act = n.actions.find(x => x.identifier === "default")
                     || (n.actions.length === 1 ? n.actions[0] : null);
            if (act) act.invoke();
        }
        if (focusClass) focusDelay.focus(focusClass);
    }

    // A kittymux agent pane: kitty focuses it (and its tab), then exactly its
    // OS window (kittymux_wmfocus). The notification's own helper would do
    // the same, but only while it lives (30s); this works from history.
    function jumpTo(item) {
        const [pid, w] = item.jump.split(":");
        const p = jumper.createObject(root, { command: [Quickshell.env("HOME") + "/.local/bin/kittymux", "act", JSON.stringify({ op: "jump", pid: Number(pid), w: w })] });
        p.running = true;
        if (item.notification) item.notification.dismiss();     // its helper exits without acting
    }
    Component { id: jumper; Process { onExited: destroy() } }

    function invokeAction(item, id) {
        const n = item.notification;
        item.leaving = true;
        const act = n ? n.actions.find(x => x.identifier === id) : null;
        if (act) act.invoke();
    }

    // Close button, right click or swipe: gone from history as well.
    function dismiss(item) {
        item.discard = true;
        item.leaving = true;
        if (item.notification) item.notification.dismiss();
    }

    // Already off screen (flung away): no exit animation, just forget it.
    function drop(item) {
        item.discard = true;
        if (item.notification) item.notification.dismiss();
        left(item);
    }

    // Called by the card when its exit animation has finished.
    function left(item) {
        item.popup = false;
        item.leaving = false;
        item.hovered = false;
        if (item.discard) remove(item);
    }

    // Every notification from one app (the center's group "clear").
    function removeApp(app) {
        for (const i of items.filter(x => x.app === app)) {
            if (i.popup) dismiss(i);
            else remove(i);
        }
    }

    function clearAll() {
        for (const i of items.slice()) {
            if (i.popup) dismiss(i);
            else remove(i);
        }
    }

    function markSeen() {
        lastSeen = Date.now();
        save();
    }

    // Open a notification from the center: its action if it's still live,
    // its app's window, and the center gets out of the way.
    function openItem(item) {
        const n = item.notification;
        if (item.jump) { jumpTo(item); setCenter(false); return; }
        if (n) {
            const act = n.actions.find(x => x.identifier === "default")
                     || (n.actions.length === 1 ? n.actions[0] : null);
            if (act) act.invoke();
        }
        if (item.focusClass) focusDelay.focus(item.focusClass);
        setCenter(false);
    }

    // Toggle the center onto a tab; with it open on the other tab, switch.
    function toggleCenter(tab, via) {
        const t = ["agents", "sound", "controls"].includes(tab) ? tab : "notifications";
        if (centerOpen && centerTab !== t) { centerTab = t; return; }
        centerTab = t;
        setCenter(!centerOpen, via);
    }

    function setCenter(open, via) {
        console.info("center: " + (open ? "open" : "close") + " via " + via + (open === centerOpen ? " (no change)" : ""));
        if (open === centerOpen) return;
        centerVia = via === "pointer" ? "pointer" : "key";
        // A click on the bell while open first closes it (focus grab), then
        // the bell toggles: don't let that one click reopen it. Keys are
        // never swallowed.
        if (open && via === "pointer" && Date.now() - closedAt < 350) return;
        centerOpen = open;
        // Toasts on screen are handed to the center by Popups (it fades them
        // as the center morphs out of the front one).
        if (!open) {
            closedAt = Date.now();
            markSeen();
        }
    }

    function remove(item) {
        items = items.filter(i => i !== item);
        if (item.notification) item.notification.dismiss();
        item.destroy();
        save();
    }

    function trim() {
        if (items.length <= maxItems) return;
        const extra = items.slice(maxItems).filter(i => !i.popup);
        items = items.filter(i => !extra.includes(i));
        for (const i of extra) {
            if (i.notification) i.notification.dismiss();
            i.destroy();
        }
    }

    Process {
        id: alertSound
        command: ["pw-play", "--volume", "0.7", "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga"]
    }

    // The app's own activation may lose the race for focus on Wayland, so
    // focus its window from here too, just after the action is delivered.
    Timer {
        id: focusDelay
        property string cls
        interval: 120
        function focus(c) { cls = c; restart(); }
        onTriggered: Hyprland.dispatch(`focuswindow class:^(${cls.replace(/\./g, "\\.")})$`)
    }

    // ── Persistence ──────────────────────────────────────────────────────
    Component.onCompleted: {
        mkdir.running = true;
        // Desktop entries are scanned lazily on first access; start the scan
        // now so the first notification can already find its app's icon.
        void DesktopEntries.applications.values.length;
    }

    Process {
        id: mkdir
        command: ["mkdir", "-p", root.stateDir]
        onExited: store.path = root.stateDir + "/notifications.json"
    }

    FileView {
        id: store
        printErrors: false
        onLoaded: {
            let data = {};
            try { data = JSON.parse(text()); } catch (e) {}
            root.dnd = !!data.dnd;
            root.lastSeen = data.lastSeen || 0;
            // Older entries may hold an in-memory image handle from a past run.
            for (const h of data.history || [])
                if (/^image:\/\/qsimage\/|\/tmp\//.test(h.icon || "")) h.icon = "";
            const restored = (data.history || []).map(h => itemComp.createObject(root, h));
            root.items = [...root.items, ...restored];
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }

    function save() {
        if (loaded) saveDelay.restart();
    }
    onDndChanged: save()

    Timer {
        id: saveDelay
        interval: 800
        onTriggered: store.setText(JSON.stringify({
            dnd: root.dnd,
            lastSeen: root.lastSeen,
            history: root.items.filter(i => !i.discard).map(i => i.toJson())
        }))
    }

    Component {
        id: itemComp
        NotifItem {}
    }

    // ── IPC: `qs ipc -p <shell> call notifs <fn>` (wrapped by bin/rice) ──
    IpcHandler {
        target: "notifs"

        function toggleDnd(): bool {
            root.dnd = !root.dnd;
            return root.dnd;
        }
        function setDnd(on: bool): void {
            root.dnd = on;
        }
        function isDnd(): bool {
            return root.dnd;
        }
        // Remove notifications by app and exact title (scripts, tests).
        function removeMatching(app: string, title: string): int {
            const hits = root.items.filter(i => i.app === app && i.title === title);
            for (const i of hits) {
                if (i.popup) root.dismiss(i);
                else root.remove(i);
            }
            return hits.length;
        }
        function count(): int {
            return root.items.length;
        }
        function dismissPopups(): void {
            for (const i of root.popups) i.leaving = true;
        }
        function clear(): void {
            root.clearAll();
        }
        // Act on the newest toast on screen, as if it were clicked.
        function openLatest(): void {
            const top = root.popups.find(i => !i.leaving);
            if (top) root.activate(top);
        }
        // Bring the most recent notification back on screen.
        function showLast(): void {
            const last = root.items.find(i => !i.popup);
            if (last) {
                last.remaining = last.expireMs || 5000;
                last.popup = true;
            }
        }
        // The bell: unread count (cleared by opening the center), DND state.
        function waybar(): string {
            const n = root.unread;
            const alt = (root.dnd ? "dnd" : "") + (root.dnd && n ? "-" : "") + (n ? "notification" : (root.dnd ? "" : "none"));
            const recent = root.items.slice(0, 8).map(i => ` ${i.app}: ${i.title}`).join("\n");
            return JSON.stringify({
                text: n ? String(n) : "",
                alt: alt,
                class: alt,
                tooltip: "󰎟 Notifications" + (root.dnd ? " (do not disturb)" : "")
                       + `\n${n} unread · ${root.items.length} total`
                       + "\n󰳽 click: open · right: do not disturb · middle: clear"
                       + (recent ? "\n\n" + recent : "")
            });
        }
    }

    IpcHandler {
        target: "center"

        // toggle/open take a tab: "notifications" (default) or "agents".
        // Toggling to the other tab while open switches instead of closing.
        // via: "key" (shortcuts) or "pointer" (the bell). The center morphs
        // for the pointer and appears instantly for keys.
        function toggle(tab: string, via: string): void {
            root.toggleCenter(tab, via);
        }
        function open(tab: string, via: string): void {
            root.centerTab = ["agents", "sound", "controls"].includes(tab) ? tab : "notifications";
            root.setCenter(true, via);
        }
        function close(): void {
            root.setCenter(false);
        }
    }
}
