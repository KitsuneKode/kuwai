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
import "icons.mjs" as IconMap

Singleton {
    id: root
    FontLoader { source: Qt.resolvedUrl("../assets/phosphor/Phosphor.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/phosphor/Phosphor-Duotone.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/phosphor/Phosphor-Bold.ttf") }
    FontLoader { source: Qt.resolvedUrl("../assets/phosphor/Phosphor-Fill.ttf") }
    function glyph(name, key) { return IconMap.glyph(name, key || "r"); }
    function phosphorForNerd(cp) { return IconMap.phosphorForNerd(cp); }
    function nerdGlyph(cp, key) { return IconMap.nerdGlyph(cp, key || "r"); }
}
