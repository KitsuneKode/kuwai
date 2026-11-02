// Phosphor icons (MIT, assets/phosphor/LICENSE; fonts in ~/.local/share/fonts/
// phosphor): name → codepoints, for components/Icon. Loaded once.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var map: ({})
    FileView {
        path: Quickshell.shellDir + "/assets/phosphor/map.json"
        printErrors: false
        onLoaded: { try { root.map = JSON.parse(text()); } catch (e) {} }
    }
    function glyph(name, key) {
        const e = map[name];
        return e && e[key] ? String.fromCodePoint(e[key]) : "";
    }
}
