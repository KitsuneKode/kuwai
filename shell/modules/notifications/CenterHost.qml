import QtQuick
import qs.config
import qs.services

QtObject {
    id: host

    property bool open: false
    property bool inIsland: false
    property Item ui: null
    readonly property string tab: Notifs.centerTab

    property string query: ""
    readonly property var terms: query.toLowerCase().split(/\s+/).filter(t => t)
    function matchesText(text) {
        if (!terms.length) return true;
        const hay = (text || "").toLowerCase();
        return terms.every(t => hay.includes(t));
    }
    function highlight(text) {
        const esc = s => (s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        if (!terms.length) return esc(text);
        const pattern = new RegExp("(" + terms.map(t => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|") + ")", "gi");
        return (text || "").split(pattern).map((part, k) => k % 2 ? `<font color="${Theme.yellow}"><b>${esc(part)}</b></font>` : esc(part)).join("");
    }
    property bool instant: false
    onQueryChanged: snap()
    onTabChanged: snap()
    function snap() { instant = true; settle.restart(); }
    readonly property Timer settle: Timer { interval: 80; onTriggered: host.instant = false }

    function tip(item, on, text, keys) { if (!ui) return; if (on) ui.tips.show(item, text, keys); else ui.tips.hide(item); }
    function currentView() { return ui ? ui.currentView() : null; }
}
