import QtQuick

QtObject {
    id: keys
    required property Item scope
    property KeyPath path: KeyPath { scope: keys.scope }
    function mainFlick() {
        let best = null;
        function visit(it) {
            if (!it || !it.visible) return;
            if (it.contentY !== undefined && it.flickableDirection !== undefined && it.contentHeight > it.height + 1
                && (!best || it.height > best.height)) best = it;
            for (const c of it.children) visit(c);
        }
        visit(scope);
        return best;
    }
    function scrollBy(f, dy) {
        const top = f.originY || 0, bottom = top + f.contentHeight - f.height;
        f.contentY = dy === Infinity ? bottom : dy === -Infinity ? top : Math.max(top, Math.min(bottom, f.contentY + dy));
    }
    function reveal(item) { if (item && path.owns(item)) path.reveal(item); }
    function handle(e, w) {
        if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false;
        if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
            const s = path.stops();
            if (!s.length) return false;
            const forward = e.key === Qt.Key_Tab && !(e.modifiers & Qt.ShiftModifier);
            const at = s.indexOf(path.holder(w ? w.activeFocusItem : null, s));
            const i = at < 0 ? (forward ? 0 : s.length - 1) : (at + (forward ? 1 : -1) + s.length) % s.length;
            return path.focusOn(s[i], forward);
        }
        const f = mainFlick();
        if (!f) return false;
        const page = f.height * 0.85, shift = !!(e.modifiers & Qt.ShiftModifier);
        const by = e.key === Qt.Key_Down ? 56 : e.key === Qt.Key_Up ? -56 : e.key === Qt.Key_PageDown ? page : e.key === Qt.Key_PageUp ? -page
            : e.key === Qt.Key_Space ? (shift ? -page : page) : e.key === Qt.Key_Home ? -Infinity : e.key === Qt.Key_End ? Infinity : 0;
        if (!by) return false;
        scrollBy(f, by);
        return true;
    }
}
