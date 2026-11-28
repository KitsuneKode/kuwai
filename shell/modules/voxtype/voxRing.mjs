export const FLOOR_DB = -72;
export const SPAN_DB = 18;

export function logical(m) {
    const s = m.scale || 1;
    const turned = (m.transform || 0) % 2 === 1;
    return { w: Math.round((turned ? m.height : m.width) / s), h: Math.round((turned ? m.width : m.height) / s) };
}

export function onShow(c, m) {
    const ws = (c.workspace || {}).name;
    if (!ws) return false;
    const special = (m.specialWorkspace || {}).name;
    return ws === (m.activeWorkspace || {}).name || (!!special && ws === special);
}

export function place(address, clients, monitors, look) {
    const c = (clients || []).find(x => x && x.address === address);
    const m = c && (monitors || []).find(x => x && x.id === c.monitor);
    if (!c || !m || !c.mapped || c.hidden || !onShow(c, m)) return null;
    const screen = logical(m);
    const win = { x: c.at[0] - m.x, y: c.at[1] - m.y, w: c.size[0], h: c.size[1] };
    const full = (c.fullscreen | 0) >= 2;
    const r = m.reserved || [0, 0, 0, 0];
    const out = look.border + look.gap + look.stroke;
    const room = !full && (c.fullscreen | 0) === 0
        && win.x - out >= r[0] && win.y - out >= r[1]
        && win.x + win.w + out <= screen.w - r[2] && win.y + win.h + out <= screen.h - r[3];
    if (room)
        return { address, monitor: m.name, win, inside: false, x: win.x - out, y: win.y - out, w: win.w + out * 2, h: win.h + out * 2, radius: look.rounding + out };
    if (full)
        return { address, monitor: m.name, win: { x: 0, y: 0, w: screen.w, h: screen.h }, inside: true, x: 0, y: 0, w: screen.w, h: screen.h, radius: 0 };
    const b = look.border;
    const x0 = Math.max(0, win.x - b), y0 = Math.max(0, win.y - b);
    const x1 = Math.min(screen.w, win.x + win.w + b), y1 = Math.min(screen.h, win.y + win.h + b);
    return { address, monitor: m.name, win, inside: true, x: x0, y: y0, w: Math.max(0, x1 - x0), h: Math.max(0, y1 - y0), radius: look.rounding + b };
}

export function quiet() {
    return { noise: FLOOR_DB + SPAN_DB, top: FLOOR_DB + SPAN_DB * 2, glow: 0 };
}

export function listen(s, peak, dtMs) {
    const was = s || quiet();
    const p = Math.max(0, Number(peak) || 0);
    const db = p > 0 ? Math.max(FLOOR_DB, 20 * Math.log10(p)) : FLOOR_DB;
    const dt = Math.max(0, dtMs) / 1000;
    const noise = p > 0 ? (db < was.noise ? db : Math.min(db, was.noise + 2 * dt)) : was.noise;
    const top = Math.max(db, was.top - 4 * dt, noise + SPAN_DB);
    const v = Math.max(0, Math.min(1, (db - noise) / (top - noise)));
    const glow = v > was.glow ? was.glow + (v - was.glow) * 0.6 : was.glow * 0.82 + v * 0.18;
    return { noise, top, glow };
}

export const PILL_STYLES = ['field', 'words', 'ticker', 'status'];

export function pillWish(style, textScale, box, stroke) {
    const target = box && box.address && box.win
        ? { address: box.address, monitor: box.monitor, x: box.win.x, y: box.win.y, w: box.win.w, h: box.win.h,
            seam: box.inside ? null : box.y + box.h - (stroke || 0) / 2 } : null;
    return { style: PILL_STYLES.includes(style) ? style : 'field', textScale: Math.max(1, Math.min(2, Number(textScale) || 1)), target };
}

export function captionWanted(style, inField) {
    return style === 'words' || style === 'ticker' ? false : !inField;
}
