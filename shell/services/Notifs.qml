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
import qs.config

Singleton {
    property real copyAskedAt: 0
    Timer {
        id: copyFallback
        interval: 1200
        onTriggered: if (Clipboard.copiedAt < root.copyAskedAt - 300)
            Moments.show({ kind: "copied", glyph: "\u{f018f}", label: "Copied", value: "", ring: -1, tone: Theme.textPrimary }, 1400)
    }
    id: root

    property var items: []                    // newest first (NotifItem)
    // Critical ones ride at the top of the stack; otherwise newest first.
    readonly property var popups: {
        const shown = items.filter(i => i.popup);
        return [...shown.filter(i => i.severity === "critical"), ...shown.filter(i => i.severity !== "critical")];
    }
    property bool dnd: false
    // Screen share / automation: mutes toasts without persisting Focus (saved dnd).
    property bool dndMute: false
    readonly property bool muted: root.dnd || root.dndMute
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
    // Bell badge: still in the center until dismissed (not cleared by opening the panel).
    readonly property int inbox: items.filter(i => !i.discard).length
    // Missed and worth acting on: unread, not on screen any more, and either
    // urgent (critical / a warning) or carrying something to do (an action).
    // The island keeps a dot for them and lists them, with their buttons, when
    // you hover its bell. Newest first.
    readonly property var missed: items.filter(i => i.time > lastSeen && !i.popup && !i.discard && !i.quiet
        && !(i.event && Kittymux.answered(i.event))          // a kittymux pane you've already been to
        && (i.severity === "critical" || i.severity === "warning" || i.urgency === NotificationUrgency.Critical || i.hasDefault || (i.actions && i.actions.length)))
        .sort((a, b) => b.time - a.time)
    // Of those, the ones a hidden island stays out for (IslandBar.outNow).
    readonly property bool missedUrgent: missed.some(i => i.severity === "critical" || i.urgency === NotificationUrgency.Critical)

    readonly property string bellBadge: inbox <= 0 ? "" : (inbox > 9 ? "9+" : String(inbox))
    readonly property color bellBadgeTone: missed.some(i => i.severity === "critical") ? Theme.critical
        : missed.length ? Theme.orange : Theme.accent
    readonly property string bellTip: dnd ? "Focus on · notifications held"
        : dndMute ? "Held while sharing"
        : inbox === 0 ? "Notifications · click · right-click list"
        : (inbox > 9 ? "9+ in center" : inbox === 1 ? "1 in center" : inbox + " in center") + " · click · right-click list"

    function bellQuickList(maxN) {
        const cap = maxN || 8;
        const out = [];
        const seen = new Set();
        const key = i => String(i.nid || "") + "|" + i.time + "|" + i.app + "|" + i.title;
        // One row per kittymux pane: its newest (finished after it asked, the
        // ask is over); "Zen loader" five times read as five things.
        const panes = new Set();
        const add = i => {
            const k = key(i);
            if (seen.has(k) || (i.jump && panes.has(i.jump))) return;
            seen.add(k); if (i.jump) panes.add(i.jump); out.push(i);
        };
        for (const i of missed) { add(i); if (out.length >= cap) return out; }
        const unreadItems = items.filter(i => i.time > lastSeen && !i.discard);
        const pri = unreadItems.filter(i => {
            if (seen.has(key(i))) return false;
            if (i.severity === "critical" || i.severity === "warning") return true;
            return sensitiveApps.test(String(i.app || ""));
        }).sort((a, b) => b.time - a.time);
        for (const i of pri) { add(i); if (out.length >= cap) return out; }
        for (const i of unreadItems.sort((a, b) => b.time - a.time)) { add(i); if (out.length >= cap) return out; }
        for (const i of items.filter(x => !x.discard).sort((a, b) => b.time - a.time)) { add(i); if (out.length >= cap) return out; }
        return out;
    }

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/rice"
    property bool loaded: false
    property var carried: []            // reload-carried notifications waiting for the history
    onLoadedChanged: if (loaded && carried.length) {
        const all = items.concat(snoozed);
        for (const n of carried) {
            const known = all.find(i => !i.notification && i.nid === n.id);
            if (known) known.notification = n;
        }
        carried = [];
    }

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        actionsSupported: true
        inlineReplySupported: true
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
            // Before the history is read, hold it: it was dropped, and its
            // row came back dead (Reply, Archive, Mark as Read did nothing).
            if (!loaded) { carried.push(n); return; }
            const known = items.concat(snoozed).find(i => !i.notification && i.nid === n.id);
            if (known) known.notification = n;
            return;
        }
        const a = NotifAdapters.adapt(n);
        if (a.silent) {
            // The clipboard pill says it, with what was copied (a thumbnail,
            // the text): one "Copied", not a bare one here and that one too.
            // Only if the clipboard didn't change (the same thing again) is
            // it said here.
            if (a.copied) { copyAskedAt = Date.now(); copyFallback.restart(); }
            n.dismiss();
            return;
        }
        const twin = a.groupKey ? items.find(i => i.groupKey === a.groupKey && i.popup && !i.leaving) : null;
        if (twin) {
            twin.absorb(n, a);
            save();
            return;
        }
        const item = itemComp.createObject(root, { notification: n });
        item.apply(n, a);
        // While the center is open the new one just lands in its list; so
        // does a quiet one (a bot's pull request, say).
        item.popup = toastsFor(item);
        // One app, one toast: a burst (14 meeting reminders) replaces its own
        // toast on screen instead of pushing everyone else's off. The earlier
        // ones stay in the history; the toast counts them (+13).
        if (item.popup && item.severity !== "critical") {
            const prev = items.filter(i => i.popup && !i.leaving && i.app === item.app && i.severity !== "critical");
            for (const p of prev) { item.burst += 1 + p.burst; p.leaving = true; }
        }
        items = [item, ...items];
        // Sound only where it earns its place: critical alerts (they also
        // break through do-not-disturb), unless the sender asked for silence.
        if (item.severity === "critical" && !(n.hints && n.hints["suppress-sound"])) alertSound.running = true;

        deliver(item, a.calm);
        // Too many on screen: the oldest steps out.
        const shown = popups.filter(i => !i.leaving);
        for (let k = maxPopups; k < shown.length; k++) shown[k].leaving = true;
        trim();
        save();
    }

    // ── Where a notification shows: one surface each ────────────────────
    //   critical / a warning        the island (it's urgent; your eye is there)
    //   someone you can reply to    the island, with Reply
    //   everything else             a toast (GitHub, mail, updates, app news)
    //   low                         the center only
    // (Settings.notifSurface "both" puts island ones in a toast too.)
    // In a fullscreen app the notch grows for what Settings.notifFullscreen
    // allows; the rest wait in the center with the missed dot. Bursts from
    // one app are one toast (+N).
    //
    // The island shows one at a time: most severe first, then newest; a
    // more severe one takes over (the current one goes back in line); at
    // most two wait, the rest become toasts. 5 s each, held under the pointer.
    function important(i) {
        return i.severity === "critical" || i.severity === "warning" || i.urgency === NotificationUrgency.Critical || canReply(i);
    }
    function rank(i) { return i.severity === "critical" || i.urgency === NotificationUrgency.Critical ? 0 : i.severity === "warning" ? 1 : canReply(i) ? 2 : 3; }
    // Live (hasFullscreen follows Hyprland's events; lastIpcObject was a stale snapshot).
    readonly property bool fullscreenNow: !!Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen
    // Fullscreen keeps the resting notch under the window. An important
    // message still grows it: IslandBar lifts onto the overlay for that
    // peek only. Settings.notifFullscreen: important · critical · off.
    function fullscreenRankOk(i) {
        if (!fullscreenNow) return true;
        const mode = Settings.notifFullscreen || "important", r = rank(i);
        if (mode === "off") return false;
        if (r === 0) return true;
        return mode === "important" && r <= 2 && !muted;
    }
    function interrupts(i) { return !i.quiet && !centerOpen && (!muted || i.severity === "critical") && fullscreenRankOk(i); }
    // Something covers the island (the assistant, a panel open in it, the
    // clipboard shelf): a peek there would play unseen behind it, so it's a
    // toast instead. Nothing lost, nothing drawn where no one can see it.
    readonly property bool islandCovered: Assistant.open || Island.panel !== "" || Clipboard.open
    // The peek is the surface in a window and over a film. Ordinary mail
    // waits in the center; toasts stay off while something is fullscreen
    // because a toast and the notch would say it twice.
    function islandFor(i) { return !i.jump && i.app !== "T3 Code" && important(i) && interrupts(i) && !islandCovered; }
    // Toast? Not for low ones, not for what the island shows (unless "both").
    // Agents (T3 Code, a kittymux pane) are a moment in the island already
    // (Moments.agentNote, kittymux's inbox): with the island as the bar, a
    // toast as well said the same thing twice. They still land in the center.
    // The assistant's "Done:" too: the notch's edge turns green and a pull
    // down opens that chat (IslandBar). Failures and "needs you" still toast.
    function agentHere(i) { return Settings.bar === "island" && !islandCovered && (i.app === "T3 Code" || !!i.jump || (i.app === "Assistant" && /^Done: /.test(i.title || ""))); }
    function toastsFor(i) {
        if (fullscreenNow) return false;           // the notch peek speaks for it, or it waits
        if (!interrupts(i) || i.severity === "low") return false;
        if (Settings.notifSurface === "both") return true;
        return !islandFor(i) && !agentHere(i);
    }
    function deliver(item, calm) {
        // Agents finishing or waiting are a moment in the island (kittymux's
        // own panes already are, from its inbox).
        if (item.app === "T3 Code") Moments.agentNote(item);
        // A kittymux pane: its popup is kittymux's decision (not for an idle
        // notice, a repeat, a short run, or the pane you're looking at), so
        // the notch says it then, once.
        else if (item.jump) Moments.kittyNote(item);
        else if (!calm && islandFor(item)) showPeek(item);
        if (item.popup) arrived();
    }

    // ── Privacy: hide message bodies for chat/mail apps (title = who) ─────
    // Private chats, matched on the app's name only (a GitHub title that says
    // "mail" is not a chat). Gmail and GitHub are previews you asked for.
    readonly property var sensitiveApps: /\b(zapzap|whatsapp|telegram|signal|discord|slack|element|messenger|beeper)\b/i
    // Sharing the screen: every body is private, even when opened.
    readonly property bool sharing: dndMute
    // Sharing comes before urgency (review 2026-11-10, finding 04): a critical
    // message still arrives (its title, the island grows for it), but its body
    // is not in the capture. Outside a share, warnings and critical ones show.
    function bodyRedacted(item) {
        if (!item) return false;
        if (sharing) return true;
        if (item.severity === "critical" || item.severity === "warning") return false;
        return Settings.notifRedactSensitive && sensitiveApps.test(String(item.app || ""));
    }
    // reveal: the person opened it on purpose (expanded, selected, the bell
    // list). That shows a chat's body too, unless the screen is being shared.
    function bodyHidden(item, reveal) { return bodyRedacted(item) && (!reveal || sharing); }
    function bodyForDisplay(item, reveal) {
        if (!item) return "";
        if (bodyHidden(item, reveal))
            return sharing ? "Hidden while sharing your screen" : "Message hidden · Open to read";
        return String(item.body || "").replace(/\s+/g, " ");
    }
    // The reading view (expanded peek, a selected row): the whole message
    // when the sender sent it, paragraphs kept; else the body.
    function fullForDisplay(item) {
        if (!item) return "";
        if (bodyHidden(item, true)) return bodyForDisplay(item, true);
        return readable(String(item.full || item.body || ""));
    }
    // Markdown and mail clutter to plain reading text (GitHub comments and
    // newsletters showed **, [text](url), # and long tracking links as-is).
    // Not Qt's MarkdownText: it could fetch remote images (tracking pixels).
    readonly property var entities: ({ amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " ", ndash: "–", mdash: "—", hellip: "…", rsquo: "’", lsquo: "‘", rdquo: "”", ldquo: "“", copy: "©", reg: "®", trade: "™", middot: "·", bull: "•" })
    function decodeEntities(t) {
        return t.replace(/&(#x[0-9a-f]{1,6}|#\d{1,7}|[a-z]{2,8});/gi, (m, e) => {
            if (e[0] === "#") {
                const n = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
                return n > 0 && n <= 0x10ffff && !(n >= 0xd800 && n <= 0xdfff) ? String.fromCodePoint(n) : m;
            }
            const v = root.entities[e.toLowerCase()];
            return v === undefined ? m : v;
        });
    }
    // A body for StyledText (toasts, rows): apps send <b> and <i>, but an
    // <img> would make the shell fetch it (a tracking pixel), so it goes.
    function styledSafe(t) { return String(t || "").replace(/<img\b[^>]*>/gi, "").replace(/<(script|style|iframe|object)\b[\s\S]*?<\/\1>/gi, ""); }
    function readable(t) {
        return decodeEntities(String(t || "")
            .replace(/\r\n?/g, "\n")
            .replace(/[\u200b-\u200d\ufeff]/g, "")                        // zero-width
            .replace(/<!--[\s\S]*?-->/g, "")
            .replace(/<(br|\/p|\/div|\/li|\/tr|\/h\d)\b[^>]*>/gi, "\n")
            .replace(/<[^>]+>/g, ""))
            .replace(/^[ \t]*(```|~~~).*$/gm, "")                           // code fences (the code stays)
            .replace(/^[ \t]*\|?[ \t]*:?-{3,}:?[ \t]*(\|[ \t]*:?-{3,}:?[ \t]*)*\|?[ \t]*$/gm, "")  // table rules
            .replace(/^[ \t]*\|(.*)\|[ \t]*$/gm, (m, row) => row.split("|").map(c => c.trim()).filter(c => c).join("  ·  "))
            .replace(/!\[[^\]]*\]\([^)]*\)/g, "")                       // images
            .replace(/\[([^\]]+)\]\((?:[^()]|\([^)]*\))*\)/g, "$1")          // [text](url) → text
            .replace(/https?:\/\/(?:www\.)?([^\/\s?#]+)[^\s)]*/g, "$1…")    // bare links → their site
            .replace(/^\s{0,3}#{1,6}\s+/gm, "")                           // headings
            .replace(/^([ \t]*)[-*+]\s+(?:\[[ xX]\]\s+)?/gm, (m, ind) => "  ".repeat(Math.min(3, Math.floor(ind.replace(/\t/g, "  ").length / 2))) + "• ")  // bullets, nesting kept
            .replace(/(\*\*|__)(.+?)\1/g, "$2").replace(/`([^`]+)`/g, "$1")  // bold, code
            .replace(/\*\*/g, "")                                          // an unclosed **
            .replace(/^\s*>\s?/gm, "")                                    // quotes
            .replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
    }

    property var peek: null
    // The screen it came up on: it stays there while it shows (it jumped
    // to the other monitor mid-read when focus moved).
    property string peekOn: ""
    property var peekQueue: []
    property bool peekHeld: false
    property bool peekExpanded: false
    // After openInCenter: NotificationsView selects this row (and optional reply).
    property var centerFocusItem: null
    property bool centerFocusReply: false
    property string centerMorphFrom: ""          // "" | "peek" | "toast"
    property var centerMorphFromRect: null
    onPeekChanged: {
        peekExpanded = false; peekFor.interval = 5000;
        if (!peek) peekOn = ""; else if (!peekOn || !Screens.present(peekOn)) peekOn = Screens.focusedName;
    }
    function showPeek(item) {
        if (!peek) { peek = item; if (!peekHeld) peekFor.restart(); return; }
        if (rank(item) < rank(peek)) {               // more urgent: it goes first
            peekQueue = [peek, ...peekQueue].slice(0, 2);
            peek = item;
            if (!peekHeld) peekFor.restart();
            return;
        }
        if (peekQueue.length < 2) {
            peekQueue = [...peekQueue, item].sort((a, b) => rank(a) - rank(b) || b.time - a.time);
            return;
        }
        // The line is full: a toast instead, so nothing is lost or late.
        if (!item.popup && interrupts(item)) { item.popup = true; arrived(); }
    }
    function nextPeek() {
        const q = peekQueue.filter(i => !i.discard && !i.leaving);
        peek = q.length ? q[0] : null;
        peekQueue = q.slice(1);
        if (peek && !peekHeld) peekFor.restart();
    }
    function dropPeek() { peekExpanded = false; peekFor.interval = 5000; nextPeek(); }
    function dismissPeekItem(item) {
        const i = item || peek;
        if (!i) return;
        peekExpanded = false;
        if (peek === i) nextPeek();
        dismiss(i);
    }
    onPeekHeldChanged: if (peekHeld) peekFor.stop(); else if (peek) peekFor.restart()
    Timer { id: peekFor; interval: 5000; onTriggered: if (!root.peekHeld) root.nextPeek() }

    // Read one in the island: the expanded peek (the whole message when the
    // sender gave it, Reply under it), from the bell's list or the center.
    // Held 45 s, and for as long as the pointer rests on it.
    // A window opening while the center holds the keyboard (a screenshot's
    // satty, an app from a notification): the center steps aside and the new
    // window gets focus. It kept the keyboard before, so Super+Q closed the
    // window behind instead of the one under your eyes.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "openwindow" || !root.centerOpen) return;
            root.setCenter(false, "pointer");
            const addr = String(event.data || "").split(",")[0];
            if (/^[0-9a-f]+$/i.test(addr)) focusNew.addr = addr, focusNew.restart();
        }
    }
    Timer {
        id: focusNew
        property string addr: ""
        interval: 120     // after the center has let go of the keyboard
        onTriggered: Hyprland.dispatch("hl.dsp.focus({window = 'address:0x" + addr + "'})")
    }
    // Read it in the island: the Read & Reply panel (modules/island/
    // ReadPanel), with the keyboard, so you can answer right there. (It used
    // to expand the floating peek, which can't take typing.)
    property var reading: null

    // A one-time code in a notification (Gmail sign-in mail, a bank, 2FA
    // texts): the code itself, so the card can show it big with Copy. ""
    // when there's none. Prefers a code right after "code / OTP / PIN";
    // never a year.
    function otpOf(item) {
        if (!item) return "";
        const t = [item.title, item.body, item.full].filter(x => x).join("\n");
        if (!/(code|otp|verif|passcode|one[- ]?time|2fa|two[- ]factor|sign[- ]?in|log[- ]?in|security|confirm|\bpin\b)/i.test(t)) return "";
        const near = t.match(/(?:code|otp|passcode|pin|is|use|enter)\W{0,3}[:\s]\s*([0-9]{3}[- ][0-9]{3}|[0-9]{4,8})\b/i);
        const any = t.match(/\b([0-9]{3}[- ][0-9]{3}|[0-9]{6,8})\b/);
        const alnum = t.match(/\b(?=[A-Z0-9]*[0-9])(?=[A-Z0-9]*[A-Z])([A-Z0-9]{6,8})\b/);
        const m = near || any || alnum;
        if (!m) return "";
        const c = m[1].replace(/[- ]/g, "");
        return /^(19|20)\d\d$/.test(c) ? "" : c;
    }
    // "482913" → "482 913"; "12345678" → "1234 5678".
    function spacedCode(c) {
        if (c.length === 6) return c.slice(0, 3) + " " + c.slice(3);
        if (c.length === 8) return c.slice(0, 4) + " " + c.slice(4);
        return c;
    }
    // Copy it (it leaves the clipboard history after a minute, as secrets
    // do), say so, and the card is done: read, then gone.
    function copyCode(item) {
        const c = otpOf(item);
        if (!c) return;
        Clipboard.pendingSecret = c;
        Quickshell.execDetached(["wl-copy", "--", c]);
        Moments.show({ kind: "copied", glyph: "\u{f018f}", label: "Code copied", value: spacedCode(c), ring: -1, tone: Theme.textPrimary }, 1600);
        const n = item.notification;
        const rd = n ? n.actions.find(x => x.identifier === "read") : null;
        if (rd) rd.invoke();
        dismiss(item);
    }
    function readInIsland(item) {
        if (!item) return;
        if (centerOpen) setCenter(false, "pointer");
        if (peek === item) dropPeek();
        reading = item;
        Island.open("read", Screens.focusedName, "pointer", "island");
    }
    function expandPeek() {
        if (!peek) return;
        peekExpanded = true;
        peekFor.interval = 12000;
        if (!peekHeld) peekFor.restart();
    }

    // Focus (dnd) and sharing (dndMute) are separate reasons to hold
    // notifications, each with its own owner: ending Focus must not lift the
    // mute and redaction a screen share put on. Only the share's end does
    // (automation.lua → `rice notifs mute-off`).
    function toggleUserDnd() {
        dnd = !dnd;
    }

    // Island peek → notification center: select the row; Reply opens the inline field.
    function openInCenter(item, reply, screenName) {
        if (!item) return;
        centerFocusItem = item;
        centerFocusReply = !!reply;
        const morphPeek = peek === item;
        const morphH = morphPeek && peekExpanded ? 172 : 76;
        if (morphPeek) {
            centerMorphFrom = "peek";
            centerMorphFromRect = { w: 460, h: morphH, r: morphH > 100 ? 28 : 38 };
            nextPeek();
        } else {
            centerMorphFrom = "";
            centerMorphFromRect = null;
        }
        peekExpanded = false;
        peekFor.interval = 5000;
        const go = s => {
            centerTab = "notifications";
            if (centerOpen && centerScreen !== s) {
                centerScreen = s;
                setCenter(false, "pointer");
                Qt.callLater(() => setCenter(true, "pointer"));
                return;
            }
            if (!centerOpen) {
                centerScreen = s;
                setCenter(true, "pointer");
            }
        };
        if (screenName) go(screenName);
        else Screens.refresh(go);
    }

    function takeCenterFocus() {
        const out = { item: centerFocusItem, reply: centerFocusReply };
        centerFocusItem = null;
        centerFocusReply = false;
        return out.item ? out : null;
    }

    // ── Card interactions ────────────────────────────────────────────────
    // A notification you act on is handled: like macOS, it leaves the history
    // as well as the screen (click, an action button, opening it from the
    // center). Ones the app withdraws go too (NotifItem: read in the app).
    // Seen ones that nobody touched clear after Settings.notifKeepSeenHours.
    //
    // Click: run the app's default action (or its only one) and bring its
    // window forward.
    function activate(item) {
        const focusClass = item.focusClass;
        item.discard = true;
        item.leaving = true;
        if (item.jump) { jumpTo(item); return; }
        if (!invokeDefault(item)) openUrl(item);
        if (focusClass) focusDelay.focus(focusClass);
    }
    function invokeDefault(item) {
        const n = item.notification;
        // A feed card (bin/rice-feeds) with a link: the shell opens the link
        // itself and asks the feed only to mark it read. Its "Open" lived in
        // the feed's memory, so after the feed restarted a click opened nothing.
        if (item.feed && item.url) {
            const rd = n ? n.actions.find(x => x.identifier === "read") : null;
            if (rd) rd.invoke();
            return false;          // → openUrl
        }
        const act = n ? (n.actions.find(x => x.identifier === "default") || (n.actions.length === 1 ? n.actions[0] : null)) : null;
        if (act) act.invoke();
        return !!act;
    }
    // Its sender gone (a restart since), a link still opens (bin/rice-feeds).
    function openUrl(item) {
        // Web and mail links only, and never with a newline or NUL smuggled in.
        const u = String(item.url || "");
        if (!/^(https?:\/\/[^\s]+|mailto:[^\s]+)$/.test(u) || /[\0\n\r]/.test(u)) return;
        // Its own transient unit (as bin/rice-feeds does): a browser started
        // from the shell's process died with the shell's next restart.
        const p = jumper.createObject(root, { command: ["systemd-run", "--user", "--collect", "--quiet", "--slice=app.slice", "--", "xdg-open", u] });
        p.running = true;
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
        if (n && n.hints && n.hints["x-rice-crash"] === "1") {
            item.discard = true;
            if (item.popup) item.leaving = true;
            else forget.later(item);
            if (id === "default") Crashes.runDiagnose(item.body);
            return;
        }
        if (n && n.hints && n.hints["x-rice-agent-limit"] === "1") {
            item.discard = true;
            if (item.popup) item.leaving = true;
            else forget.later(item);
            if (id === "default") root.toggleCenter("agents", "pointer", Screens.focusedName);
            return;
        }
        item.discard = true;
        if (item.popup) item.leaving = true;
        else forget.later(item);
        const act = n ? n.actions.find(x => x.identifier === id) : null;
        if (act) act.invoke();
    }

    // Reply from the notification (apps that offer it: chat apps). Sent
    // through the app, then the notification is handled, like an action.
    function canReply(item) { return !!item && !!item.notification && item.notification.hasInlineReply; }
    function reply(item, text) {
        const n = item.notification;
        if (!n || !n.hasInlineReply || !String(text || "").trim()) return;
        n.sendInlineReply(String(text));
        item.discard = true;
        if (item.popup) item.leaving = true;
        else forget.later(item);
    }

    // Snooze: out of the list (and the island's "missed") until `until`,
    // then back as a fresh toast. Kept across restarts.
    property var snoozed: []
    function snooze(item, until) {
        item.snoozedUntil = until;
        item.popup = false;
        item.leaving = false;
        items = items.filter(i => i !== item);
        snoozed = [...snoozed.filter(i => i !== item), item];
        save();
    }
    function wake(item) {
        item.snoozedUntil = 0;
        snoozed = snoozed.filter(i => i !== item);
        item.time = Date.now();
        item.discard = false;
        item.popup = toastsFor(item);
        items = [item, ...items];
        deliver(item, false);
        save();
    }
    Timer {
        interval: 20000; repeat: true; triggeredOnStart: true
        running: root.snoozed.length > 0
        onTriggered: { for (const i of root.snoozed.slice()) if (i.snoozedUntil <= Date.now()) root.wake(i); }
    }
    // The choices, from now: an hour; this evening (before 6 pm); tomorrow 9.
    function snoozeChoices() {
        const now = new Date(), out = [{ label: "1 hour", until: Date.now() + 3600000 }];
        if (now.getHours() < 18) { const e = new Date(now); e.setHours(19, 0, 0, 0); out.push({ label: "This evening", until: e.getTime() }); }
        const t = new Date(now); t.setDate(t.getDate() + 1); t.setHours(9, 0, 0, 0);
        out.push({ label: "Tomorrow", until: t.getTime() });
        return out;
    }

    // Close button, right click or swipe: gone from history as well.
    function dismiss(item) {
        item.discard = true;
        item.leaving = true;
        if (item.notification) item.notification.dismiss();
    }

    // Already off screen (flung away): no exit animation, just forget it.
    // Swiped or ×'d from a list (the notch's, the center's): gone from the
    // center; one on screen leaves too. A kittymux pane's "needs you" is
    // answered with it, so the notch and kittymux's inbox agree.
    function discard(item) {
        if (!item) return;
        if (item.event && !Kittymux.answered(item.event)) Kittymux.ack(item.event);
        if (item.popup) dismiss(item);
        else remove(item);
    }
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
        if (item.jump) jumpTo(item);
        else if (!invokeDefault(item)) openUrl(item);
        if (item.focusClass) focusDelay.focus(item.focusClass);
        setCenter(false);
        // Handled: out of the history once the center has folded away.
        forget.later(item);
    }
    Timer {
        id: forget
        property var queue: []
        function later(item) { queue = [...queue, item]; restart(); }
        interval: 400
        onTriggered: { for (const i of queue) if (root.items.includes(i)) root.remove(i); queue = []; }
    }

    // Toggle the center onto a tab; with it open on the other tab, switch.
    // `screenName`: the screen the click was on (a surface passes its own);
    // without it (a shortcut) Hyprland is asked which screen has focus.
    property string centerScreen: ""
    function toggleCenter(tab, via, screenName) {
        const go = s => {
            const t = ["agents", "sound", "controls"].includes(tab) ? tab : "notifications";
            if (centerOpen && centerTab !== t && s === centerScreen) { centerTab = t; return; }
            if (centerOpen && s !== centerScreen) {           // open elsewhere: bring it here
                // (closedAt cleared: the reopen fell inside the click guard and was
                // dropped, so the center closed on one screen and never came up here)
                centerTab = t; centerScreen = s; setCenter(false, via); closedAt = 0; Qt.callLater(() => setCenter(true, via)); return;
            }
            centerTab = t;
            if (!centerOpen) centerScreen = s;
            setCenter(!centerOpen, via);
        };
        if (screenName) go(screenName); else Screens.refresh(go);
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
            // Badge is the inbox (rows until dismissed). lastSeen only retires the
            // "missed" dot and the Unread filter after you've opened the center.
            markSeen();
        }
    }

    function markAllRead() {
        lastSeen = Date.now();
        save();
    }

    function remove(item) {
        items = items.filter(i => i !== item);
        if (item.notification) item.notification.dismiss();
        item.destroy();
        save();
    }

    // Seen and untouched for a day (by default): cleared, so the center holds
    // what is still news. Checked on load and every ten minutes.
    function sweepSeen() {
        const hours = Settings.notifKeepSeenHours;
        if (!loaded || hours <= 0) return;
        const cutoff = Date.now() - hours * 3600000;
        const old = items.filter(i => !i.popup && i.time <= lastSeen && i.time < cutoff);
        for (const i of old) remove(i);
    }
    Timer { interval: 600000; running: root.loaded; repeat: true; triggeredOnStart: true; onTriggered: root.sweepSeen() }

    // History: at most maxItems, and at most perApp from any one app, so a
    // noisy app can't push everyone else's out.
    readonly property int perApp: 50
    function trim() {
        const seen = {};
        const over = items.filter(i => !i.popup && (seen[i.app] = (seen[i.app] || 0) + 1) > perApp);
        const rest = items.filter(i => !over.includes(i));
        const extra = over.concat(rest.slice(maxItems).filter(i => !i.popup));
        if (!extra.length) return;
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
        // The class comes from the sending app: keep app-ID characters only, so
        // nothing it contains can end the Lua string this is pasted into.
        onTriggered: {
            const safe = String(cls).replace(/[^A-Za-z0-9._-]/g, "");
            if (safe) Hyprland.dispatch(`hl.dsp.focus({window = [[class:^(${safe.replace(/\./g, "\\.")})$]]})`);
        }
    }

    // ── Persistence ──────────────────────────────────────────────────────
    Component.onCompleted: {
        mkdir.running = true;
        // A share may already be running (this shell restarted mid-share): the
        // compositor knows, and mutes us again (hypr/kuwai/automation.lua).
        Hyprland.dispatch("kuwai.privacy_resync()");
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
            root.items = [...root.items, ...restored.filter(i => !(i.snoozedUntil > 0))];
            root.snoozed = restored.filter(i => i.snoozedUntil > 0);
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
            history: [...root.items, ...root.snoozed].filter(i => !i.discard).map(i => i.toJson())
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
            root.toggleUserDnd();
            return root.dnd;
        }
        function setDnd(on: bool): void {
            root.dnd = on;
        }
        function setDndMute(on: bool): void {
            root.dndMute = on;
        }
        function isDnd(): bool {
            return root.muted;
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
            const alt = (root.muted ? "dnd" : "") + (root.muted && n ? "-" : "") + (n ? "notification" : (root.muted ? "" : "none"));
            const recent = root.items.slice(0, 8).map(i => ` ${i.app}: ${i.title}`).join("\n");
            const why = root.dnd ? (root.dndMute ? " (focus + sharing)" : " (focus)") : (root.dndMute ? " (sharing)" : "");
            return JSON.stringify({
                text: n ? String(n) : "",
                alt: alt,
                class: alt,
                tooltip: "󰎟 Notifications" + (root.muted ? " (do not disturb)" + why : "")
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
