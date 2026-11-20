// A keyboard path into a part of a surface whose keyboard usually stays
// elsewhere (the center keeps it in its search field). Its stops are the
// items under `scope` that take Tab (activeFocusOnTab), shown and enabled,
// in the order they are declared. enter() gives the first (or last) one the
// keyboard; from there each control answers its own keys and Tab follows
// Qt's chain. step() moves to the next or previous stop (an arrow nothing
// used); reveal() scrolls every Flickable around an item so it is seen.
// `route(event)` is the scope's way back: Esc, or a typed character, return
// to `home` (the search field) with the character.
import QtQuick

QtObject {
    id: path
    required property Item scope
    property Item home: null
    function stops() {
        const out = [];
        function visit(it) {
            if (!it || !it.visible || it.opacity <= 0.01 || it.enabled === false) return;
            if (it !== path.scope && it.activeFocusOnTab) out.push(it);
            for (const c of it.children) visit(c);
        }
        visit(scope);
        return out;
    }
    function owns(item) {
        for (let p = item; p; p = p.parent) if (p === scope) return true;
        return false;
    }
    function holder(item, list) {
        for (let p = item; p && p !== scope; p = p.parent) if (list.indexOf(p) >= 0) return p;
        return null;
    }
    function focusOn(it, forward) {
        if (!it) return false;
        it.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        reveal(it);
        return true;
    }
    function enter(forward) {
        const s = stops();
        return s.length ? focusOn(forward ? s[0] : s[s.length - 1], forward) : false;
    }
    // From the item holding the keyboard to the next stop; past the first, home.
    function step(from, forward) {
        const s = stops(), at = s.indexOf(holder(from, s));
        const i = at < 0 ? (forward ? 0 : s.length - 1) : at + (forward ? 1 : -1);
        if (i < 0) { goHome(""); return true; }
        return i < s.length ? focusOn(s[i], forward) : true;
    }
    function goHome(text) {
        if (!home) return false;
        home.forceActiveFocus(Qt.OtherFocusReason);
        if (text && home.insert) home.insert(home.cursorPosition, text);
        return true;
    }
    // Keys a control in the scope didn't use: Esc and typing go home,
    // ↑↓ walk the stops.
    function route(e) {
        const plain = !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
        if (e.key === Qt.Key_Escape) return goHome("");
        if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) {
            const w = scope.Window.window;
            return step(w ? w.activeFocusItem : null, e.key === Qt.Key_Down);
        }
        if (plain && e.text.length === 1 && e.text > " " && e.text !== "\u007f") return goHome(e.text);
        return false;
    }
    function reveal(item) {
        for (let p = item.parent; p; p = p.parent) {
            if (p.contentItem === undefined || p.contentY === undefined || p.flickableDirection === undefined) continue;
            const r = item.mapToItem(p.contentItem, 0, 0), pad = 8;
            if (p.contentHeight > p.height) {
                if (r.y - pad < p.contentY) p.contentY = Math.max(0, r.y - pad);
                else if (r.y + item.height + pad > p.contentY + p.height) p.contentY = Math.min(p.contentHeight - p.height, r.y + item.height + pad - p.height);
            }
            if (p.contentWidth > p.width) {
                if (r.x - pad < p.contentX) p.contentX = Math.max(0, r.x - pad);
                else if (r.x + item.width + pad > p.contentX + p.width) p.contentX = Math.min(p.contentWidth - p.width, r.x + item.width + pad - p.width);
            }
        }
    }
}
