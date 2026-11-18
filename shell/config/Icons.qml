// Phosphor icons (MIT, assets/phosphor/LICENSE): name → codepoints, for
// components/Icon. Loaded once.
//
// The fonts come with the shell (assets/phosphor/*.ttf) and are loaded here.
// They used to be expected in ~/.local/share/fonts, where nothing put them:
// on a machine that wasn't the author's every icon drew as stray letters
// (found by the rehearsal, which has no home directory to lean on).
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var map: ({})
    FontLoader { source: Qt.resolvedUrl("../assets/phosphor/Phosphor.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/phosphor/Phosphor-Duotone.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/phosphor/Phosphor-Bold.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/phosphor/Phosphor-Fill.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/phosphor/Phosphor-Light.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/phosphor/Phosphor-Thin.ttf") }
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
