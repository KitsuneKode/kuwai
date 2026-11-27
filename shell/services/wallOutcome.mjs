/**
 * What awww shows, per screen (": DP-3: 2560x1440, … image: /path").
 * @param {string} text
 * @returns {Record<string, string>}
 */
export function parseShown(text) {
    const m = /** @type {Record<string, string>} */ ({});
    for (const l of String(text || "").split("\n")) {
        const x = l.match(/^:?\s*([^:\s]+):.*image:\s*(.+)$/);
        if (x) m[x[1]] = x[2].trim();
    }
    return m;
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
    if (!keys.length || !Object.keys(now || {}).length) return false;
    if (wanted && keys.every(k => before[k] === wanted)) return false;
    return keys.every(k => now[k] === before[k]) && !Object.keys(now).some(k => now[k] === wanted);
}

/**
 * The one sentence for it.
 * @param {string} why  the change's own reason ("unreadable", …)
 * @returns {string}
 */
export function sentence(why) {
    return why === "unreadable" ? "That picture couldn't be opened" : "The wallpaper couldn't be changed";
}
