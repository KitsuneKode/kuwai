pragma Singleton

// Emoji and Nerd-font glyphs for the launcher's `:` and `;` modes, from kuwai's
// own lists (lib/lists/, rebuilt by bin/kuwai-lists from Unicode's data and the
// Nerd Font itself), so they work without HyDE. Read and parsed once,
// the first time either mode is used, then kept: the launcher itself is
// rebuilt on every open and must not re-parse 12k lines each time.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string dir: Quickshell.shellDir + "/../lib/lists"
    property bool emojiMissing: false      // its list isn't there (a partial install)
    property bool glyphsMissing: false
    property var emoji: []          // [{ ch, name, hay }]
    property var glyphs: []
    property bool wantEmoji: false
    property bool wantGlyphs: false

    function search(list, q, limit) {
        const words = q.toLowerCase().split(/\s+/).filter(w => w);
        const out = [];
        for (const e of list) {
            if (words.every(w => e.hay.includes(w))) {
                out.push(e);
                if (out.length >= limit) break;
            }
        }
        return out;
    }

    FileView {
        path: root.wantEmoji ? root.dir + "/emoji.db" : ""
        printErrors: false
        onLoadFailed: root.emojiMissing = true
        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                const i = line.indexOf(" ");
                if (i <= 0) continue;
                const ch = line.slice(0, i), rest = line.slice(i + 1);
                out.push({ ch: ch, name: rest.split(" ").slice(0, 4).join(" "), hay: rest.toLowerCase() });
            }
            root.emoji = out;
        }
    }
    FileView {
        path: root.wantGlyphs ? root.dir + "/glyph.db" : ""
        printErrors: false
        onLoadFailed: root.glyphsMissing = true
        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                const i = line.indexOf("\t");
                if (i <= 0) continue;
                const ch = line.slice(0, i), name = line.slice(i + 1);
                out.push({ ch: ch, name: name, hay: name.toLowerCase().replace(/[-_]/g, " ") });
            }
            root.glyphs = out;
        }
    }
}
