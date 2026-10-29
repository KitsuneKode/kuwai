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
        }
    ]

    function adapt(n) {
        const rule = rules.find(r => r.match(n));
        const out = rule ? rule.adapt(n) : generic(n);
        if (!out.icon) out.icon = imageOrIcon(n);
        out.severity = severityOf(n, out.severity);
        return out;
    }

    // Critical is the sender's call (urgency); it always wins. Warnings are
    // the adapter's call, or the wording's: "battery low", "failed", …
    readonly property var warningWords: /\b(warning|battery low|low battery|critically low|failed|failure|error|limit reached|disconnected|overheat\w*)\b/i
    function severityOf(n, suggested) {
        if (n.urgency === NotificationUrgency.Critical) return "critical";
        if (suggested) return suggested;
        const category = (n.hints && n.hints.category) || "";
        if (/error|warning/.test(category) || warningWords.test(n.summary + " " + n.body)) return "warning";
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
