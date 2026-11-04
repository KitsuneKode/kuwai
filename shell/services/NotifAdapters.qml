// Per-app adapters: turn whatever an app sends over D-Bus into what the card
// should say. Apps are inconsistent (T3 Code's summary is always "Thread
// completed" and the thread is in the body; Ghostty sends an empty app name),
// so each rule below rewrites one app, and everything else gets the generic
// treatment. To support a new app, add an entry to `rules`.
//
// adapt() returns a plain object:
//   app         label shown in the card header
//   title       the headline
//   body        secondary text (may be empty)
//   status      small status line under the text (may be empty)
//   statusGlyph Nerd Font glyph for the status line
//   statusTone  "positive" | "caution" | "critical" | ""
//   icon        image source for the app icon ("" → glyph fallback)
//   groupKey    cards with the same key replace each other instead of stacking
//   focusClass  Hyprland window class to focus after the default action
//   severity    "critical" | "warning" | "normal" | "low" (optional: derived
//               from urgency and wording when an adapter doesn't set it)
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    readonly property var rules: [
        {
            // T3 Code: "Thread completed" / "Usage limit reached" + thread title
            match: n => /^T3 Code/.test(n.appName),
            adapt: n => {
                const thread = n.body || n.summary;
                const s = n.summary.toLowerCase();
                const tone = /fail|error/.test(s) ? "critical"
                           : /limit|input|approv|waiting|question|permission/.test(s) ? "caution"
                           : /complet|done|finish/.test(s) ? "positive" : "";
                const glyph = tone === "critical" ? "\u{f0028}"          // alert-circle
                            : /limit/.test(s) ? "\u{f04c5}"              // speedometer
                            : tone === "caution" ? "\u{f0b79}"           // chat-question
                            : tone === "positive" ? "\u{f05e0}" : "";   // check-circle
                return {
                    app: "T3 Code",
                    title: thread,
                    body: "",
                    status: n.body ? n.summary : "",
                    statusGlyph: glyph,
                    statusTone: tone,
                    icon: root.entryIcon("t3code") || root.entryIcon("com.t3tools.T3Code"),
                    severity: tone === "caution" || tone === "critical" ? "warning" : "",
                    groupKey: "t3:" + thread,
                    focusClass: "com.t3tools.T3Code"
                };
            }
        },
        {
            // Ghostty (OSC 9/777, command-finished, and Claude Code inside it)
            // sends no app name; its icon name comes through the image hint.
            match: n => n.desktopEntry === "com.mitchellh.ghostty" || /^ghostty$/i.test(n.appName),
            adapt: n => {
                const claude = /claude/i.test(n.summary);
                // "Claude Code" as the summary only repeats the header label.
                const bare = claude && /^claude code$/i.test(n.summary.trim()) && n.body;
                return {
                    app: claude ? "Claude Code" : "Ghostty",
                    title: bare ? n.body : (n.summary || "Ghostty"),
                    body: bare ? "" : n.body,
                    status: "",
                    statusGlyph: "",
                    statusTone: "",
                    icon: root.entryIcon("com.mitchellh.ghostty"),
                    groupKey: "ghostty:" + n.summary + "\n" + n.body,
                    focusClass: ""
                };
            }
        },
        {
            // Cider (4.0.9+) sends track changes as title + artist only: no
            // icon, no image hint. Its MPRIS player already has the new cover
            // (it updates just before the notification), so take it from there.
            match: n => n.desktopEntry === "cider" || /^cider$/i.test(n.appName),
            adapt: n => {
                const out = root.generic(n);
                const p = Array.from(Media.players || []).find(p => /cider/i.test((p.dbusName || "") + " " + (p.identity || "")));
                if (p && p.trackArtUrl && (!p.trackTitle || p.trackTitle === n.summary)) out.icon = p.trackArtUrl;
                return out;
            }
        }
    ]

    // "Copied to clipboard" confirmations (satty, grimblast, pickers…): the
    // clipboard island already shows every copy, with the thing itself, so
    // these would only say it twice. They're dropped, not shown or kept.
    function isCopyConfirmation(n) {
        const t = ((n.summary || "") + " " + (n.body || "")).trim();
        return t.length < 140 && /^(the )?(image|screenshot|text|filepath|colou?r|link|path)?\s*(was )?copied (to|into) (the )?clipboard\b/i.test(t);
    }

    function adapt(n) {
        const rule = rules.find(r => r.match(n));
        const out = rule ? rule.adapt(n) : generic(n);
        out.silent = isCopyConfirmation(n) || isNowPlaying(n);
        // kittymux sends its own art (the agent's mark with its mascot); show
        // the agent's real brand mark instead.
        if (/^kittymux$/i.test(n.appName || "")) {
            const m = String(n.appIcon || n.image || "").match(/notify\/([\w-]+)\.png$/);
            const b = m ? Kittymux.brand(m[1]) : "";
            if (b) out.icon = b;
        }
        // kittymux names the agent pane it's about (bin/mux-notify hints):
        // a click jumps there through kittymux, even from history later.
        const h = n.hints || {};
        const kpid = h["x-kittymux-pid"], kwin = h["x-kittymux-window"];
        out.jump = /^\d+$/.test(String(kpid || "")) && /^\d+$/.test(String(kwin || "")) ? kpid + ":" + kwin : "";
        if (!out.icon) out.icon = imageOrIcon(n);
        out.severity = severityOf(n, out.severity);
        return out;
    }

    // A music player announcing the song (Cider, Spotify…): the island
    // already shows what's playing, so it neither toasts nor piles up in the
    // center. Its errors and anything else it says (sign-in, updates) still
    // come through: only the "now playing" kind is dropped — the song's own
    // title or artist, or the album art with nothing to act on.
    readonly property var playerApps: /^(cider|spotify|music|apple music|rhythmbox|amberol|tidal|tidal-hifi|youtube music|elisa|strawberry|lollypop|ncspot|mpd|mpdris|g4music|gapless|feishin|supersonic)$/i
    function isNowPlaying(n) {
        if (!playerApps.test(String(n.appName || "").trim())) return false;
        if (n.urgency === NotificationUrgency.Critical) return false;
        const text = (n.summary || "") + " " + (n.body || "");
        if (warns(text)) return false;
        const p = Media.active;
        const norm = x => String(x || "").toLowerCase().trim();
        const t = norm(text);
        const song = p && ((norm(p.trackTitle).length > 1 && t.includes(norm(p.trackTitle))) || (norm(p.trackArtist).length > 1 && t.includes(norm(p.trackArtist))));
        const art = !!n.image && !(n.actions && n.actions.some(a => a.identifier !== "default"));
        return song || art;
    }

    // Critical is the sender's call (urgency); it always wins. Warnings are
    // the adapter's call, or the wording's: "battery low", "failed", …
    readonly property var warningWords: /\b(warning|battery low|low battery|critically low|failed|failure|errors?|limit reached|disconnected|overheat\w*)\b/i
    // Good news that mentions failure isn't a warning: "0 failed", "no
    // errors", or a title that says it passed / succeeded.
    function warns(text) {
        const t = String(text || "").replace(/\b(0|no|zero)\s+(failed|failures?|errors?|warnings?)\b/gi, "");
        return warningWords.test(t);
    }
    function severityOf(n, suggested) {
        if (n.urgency === NotificationUrgency.Critical) return "critical";
        if (suggested) return suggested;
        const category = (n.hints && n.hints.category) || "";
        const good = /\b(passed|succeeded|successful(ly)?|completed|done)\b/i.test(n.summary || "") && !warns(n.summary);
        if (/error|warning/.test(category) || (!good && warns(n.summary + " " + n.body))) return "warning";
        if (n.urgency === NotificationUrgency.Low) return "low";
        return "normal";
    }

    function generic(n) {
        const entry = lookupEntry(n);
        return {
            app: n.appName || (entry ? entry.name : "") || "Notification",
            title: n.summary,
            body: n.body,
            status: "",
            statusGlyph: "",
            statusTone: "",
            icon: imageOrIcon(n),
            groupKey: "",
            focusClass: ""
        };
    }

    // ── Icon resolution ──────────────────────────────────────────────────
    // Order: the notification's own image (screenshots, album art, avatars),
    // its app icon, then the icon of its desktop entry, looked up by the
    // desktop-entry hint or, failing that, by app name.
    function imageOrIcon(n) {
        if (n.image) return n.image;
        const own = iconSource(n.appIcon);
        if (own) return own;
        const entry = lookupEntry(n);
        return entry ? iconSource(entry.icon) : "";
    }

    // An icon that survives a restart: the notification's own image may be
    // an in-memory handle (image://qsimage/…) or a temp file that's gone.
    function lastingIcon(n, icon) {
        if (!/^image:\/\/qsimage\//.test(icon) && !/^file:\/\/\/tmp\//.test(icon)) return icon;
        const own = iconSource(n.appIcon);
        if (own && !/^file:\/\/\/tmp\//.test(own)) return own;
        const entry = lookupEntry(n);
        return entry ? iconSource(entry.icon) : "";
    }

    // For history entries that lost their icon: the app's, by name.
    function iconForApp(app) {
        const e = DesktopEntries.heuristicLookup(app);
        return e ? iconSource(e.icon) : "";
    }

    function lookupEntry(n) {
        return (n.desktopEntry && (DesktopEntries.byId(n.desktopEntry) || DesktopEntries.heuristicLookup(n.desktopEntry)))
            || (n.appName && DesktopEntries.heuristicLookup(n.appName))
            || null;
    }

    function entryIcon(id) {
        const e = DesktopEntries.byId(id);
        return e ? iconSource(e.icon) : "";
    }

    function iconSource(icon) {
        if (!icon) return "";
        if (icon.startsWith("/")) return "file://" + icon;
        if (/^(file|image|https?):/.test(icon)) return icon;
        return Quickshell.iconPath(icon, true);
    }
}
