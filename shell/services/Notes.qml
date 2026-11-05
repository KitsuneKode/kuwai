pragma Singleton

// Quick notes: one line from the launcher ("note buy milk") or `rice note …`,
// appended to ~/Notes/inbox.md as a timestamped Markdown list item. Plain
// text you own: open it in any editor, sync it however you like.
// (No braces before the pragma: Quickshell's scanner stops at the first.)

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string file: (Quickshell.env("RICE_NOTES") || Quickshell.env("HOME") + "/Notes") + "/inbox.md"
    property int added: 0

    // The line goes in as an argument ("$2"), never into the command.
    function add(text) {
        const t = String(text || "").trim();
        if (!t) return false;
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm");
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf -- "- %s · %s\\n" "$3" "$2" >> "$1"', "sh", root.file, t, stamp]);
        added++;
        Moments.show({ kind: "note", glyph: "\u{f0219}", label: "Noted", value: "", ring: -1, tone: "#ffffff" }, 1400);
        return true;
    }
    function open() { Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && touch "$1" && xdg-open "$1"', "sh", root.file]); }

    IpcHandler {
        target: "note"
        function add(text: string): bool { return root.add(text); }
        function open(): void { root.open(); }
    }
}
