/**
 * @param {string} p
 * @returns {string}
 */
export function normalizePath(p) {
    const s = String(p || "").trim();
    if (!s) return "";
    const collapsed = s.replace(/\/+/g, "/");
    return collapsed.length > 1 && collapsed.endsWith("/") ? collapsed.slice(0, -1) : collapsed;
}

/**
 * What awww shows, per screen (": DP-3: 2560x1440, … image: /path"),
 * preferring canonical realpath lines when present.
 * @param {string} text
 * @returns {Record<string, string>}
 */
export function parseShown(text) {
    const m = /** @type {Record<string, string>} */ ({});
    for (const l of String(text || "").split("\n")) {
        const r = l.match(/^kuwai-real (\S+) (\/.+)$/);
        if (r) { m[r[1]] = normalizePath(r[2]); continue; }
        const x = l.match(/^:?\s*([^:\s]+):.*image:\s*(.+)$/);
        if (x && !m[x[1]]) m[x[1]] = normalizePath(x[2]);
    }
    return m;
}

/**
 * @param {string} text
 * @returns {string}
 */
export function parseWanted(text) {
    const m = String(text || "").match(/^kuwai-wanted (.*)$/m);
    return m ? normalizePath(m[1]) : "";
}

/**
 * The picture really didn't change: every screen shows what it showed
 * before, and that wasn't already the picture asked for. Anything unknown
 * counts as changed, so a doubt never says it failed.
 * @param {Record<string, string>} before
 * @param {Record<string, string>} now
 * @param {string} wanted  the new picture, resolved
 * @returns {boolean}
 */
export function unchanged(before, now, wanted) {
    const keys = Object.keys(before || {});
    const nowKeys = Object.keys(now || {});
    if (!keys.length || !nowKeys.length) return false;
    const w = normalizePath(wanted);
    if (w && keys.every(k => normalizePath(before[k]) === w)) return false;
    return keys.every(k => normalizePath(now[k]) === normalizePath(before[k]))
        && !nowKeys.some(k => w && normalizePath(now[k]) === w);
}

/**
 * The one sentence for it.
 * @param {string} why  the change's own reason ("unreadable", …)
 * @returns {string}
 */
export function sentence(why) {
    return why === "unreadable" ? "That picture couldn't be opened" : "The wallpaper couldn't be changed";
}
