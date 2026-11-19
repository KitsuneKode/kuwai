// What ContextMenu.qml decides, kept apart from how it draws so it can be
// tested (tests/shell/context-menu.test.mjs). Entries are the menu's
// ContextMenuItem / CheckboxItem / Label / Separator objects: { kind, visible,
// enabled, text, glyph, checked }.

export function actionable(e) {
    return !!e && (e.kind === "item" || e.kind === "checkbox") && e.enabled !== false;
}

// The entries to draw: hidden ones out, and no separator at either end or
// next to another (a group whose items are all hidden leaves no double line).
export function arrange(list) {
    const out = [];
    const n = list ? list.length : 0;
    for (let i = 0; i < n; i++) {
        const e = list[i];
        if (!e || e.visible === false) continue;
        if (e.kind === "separator" && (!out.length || out[out.length - 1].kind === "separator")) continue;
        out.push(e);
    }
    while (out.length && out[out.length - 1].kind === "separator") out.pop();
    return out;
}

// The next row the arrows land on: actionable rows only, wrapping round.
// From -1 (nothing lit), down lands on the first and up on the last.
export function step(entries, from, dir) {
    const n = entries.length;
    if (!n) return -1;
    let i = from < 0 ? (dir > 0 ? -1 : n) : from;
    for (let k = 0; k < n; k++) {
        i = (i + dir + n) % n;
        if (actionable(entries[i])) return i;
    }
    return -1;
}

export function first(entries) { return step(entries, -1, 1); }
export function last(entries) { return step(entries, -1, -1); }

// Typing a letter lights the next row that starts with it (after the lit one).
export function typeahead(entries, from, ch) {
    const c = String(ch || "").toLowerCase();
    if (!c.trim()) return from;
    const n = entries.length;
    for (let k = 1; k <= n; k++) {
        const i = ((from < 0 ? -1 : from) + k + n) % n;
        const e = entries[i];
        if (actionable(e) && String(e.text || "").trim().toLowerCase().startsWith(c)) return i;
    }
    return from;
}

// Where the card goes: at the point, flipped to the other side of it when it
// would run out of its bounds there, then kept `m` inside them. ox / oy say
// which corner it grows from (0 the near side, 1 the far).
export function place(px, py, w, h, bw, bh, m) {
    let x = px, y = py, ox = 0, oy = 0;
    if (x + w > bw - m) {
        if (px - w >= m) { x = px - w; ox = 1; } else x = bw - m - w;
    }
    if (y + h > bh - m) {
        if (py - h >= m) { y = py - h; oy = 1; } else y = bh - m - h;
    }
    return { x: Math.max(m, x), y: Math.max(m, y), ox, oy };
}
