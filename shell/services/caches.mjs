// @ts-check
// Bounds for the shell's caches that grow with use, kept out of QML so
// `bun test tests/shell/caches.test.mjs` can drive them for hours of
// synthetic use. Loaded as written (Qt's engine: no object spread, no regex
// lookbehind, no named groups). Quickshell reloads on QML changes only:
// after editing this file, save a QML file that imports it too.

// ── Keyed by a live list (Clipboard's renders, thumbs, fileInfo) ────────

/**
 * A cache keyed by entry refs, minus refs that are no longer live, and at
 * most `cap` of the rest (the ones nearest the front of `live`, which is
 * newest first). Unchanged input comes back as is, so the shell sees no
 * property change when there's nothing to forget.
 * @template T
 * @param {Record<string, T>} map
 * @param {string[]} live   refs still in the history, newest first
 * @param {number} cap
 * @returns {Record<string, T>}
 */
export function pruneKeyed(map, live, cap) {
    const rank = /** @type {Record<string, number>} */ ({});
    for (let i = 0; i < live.length; i++) if (rank[live[i]] === undefined) rank[live[i]] = i;
    const kept = Object.keys(map || {}).filter(k => rank[k] !== undefined);
    const total = Object.keys(map || {}).length;
    if (kept.length === total && total <= cap) return map;
    kept.sort((a, b) => rank[a] - rank[b]);
    const out = /** @type {Record<string, T>} */ ({});
    for (const k of kept.slice(0, Math.max(0, cap))) out[k] = map[k];
    return out;
}

// ── The assistant's rendered blocks (OllamaService.htmlCache) ───────────
// A finished block renders once; the block being written re-renders as it
// grows, each version under its own key. A version is superseded by the
// next one of the same block (its text is a prefix of the new text): those
// go at once. The rest are bounded by total size (key + HTML, in UTF-16
// units: 2,000,000 ≈ 4 MB) and count, oldest first. An entry younger than
// `minAgeMs` is never evicted: a block on screen that was just evicted
// would ask again at once and push out the next one, a render loop; with
// the guard, more on screen than the cap holds costs one re-render per
// block every `minAgeMs`, not a spin.

/** @typedef {{ kind: string, lang?: string, text: string, live?: boolean }} Block */
/** @typedef {{ html: string, kind: string, lang: string, text: string, live: boolean, size: number, at: number }} HtmlEntry */
/** @typedef {{ map: Map<string, HtmlEntry>, live: Set<string>, chars: number }} HtmlCache */

export const HTML_MAX_CHARS = 2000000;
export const HTML_MAX_ENTRIES = 1500;
export const HTML_MIN_AGE_MS = 5000;

/** @returns {HtmlCache} */
export function htmlCache() { return { map: new Map(), live: new Set(), chars: 0 }; }

/** @param {Block} b */
export function blockKey(b) { return b.kind + (b.live ? "~" : "") + "\u0001" + (b.lang || "") + "\u0001" + b.text; }

/**
 * @param {HtmlCache} c
 * @param {Block} b
 * @returns {string | undefined}
 */
export function htmlGet(c, b) {
    const e = c.map.get(blockKey(b));
    return e ? e.html : undefined;
}

/** @param {HtmlCache} c @param {string} k */
function drop(c, k) {
    const e = c.map.get(k);
    if (!e) return;
    c.map.delete(k);
    c.live.delete(k);
    c.chars -= e.size;
}

/**
 * Store a block's HTML. Mutates `c` (the shell bumps its own tick).
 * @param {HtmlCache} c
 * @param {Block} b
 * @param {string} html
 * @param {number} now  epoch ms
 * @param {{ maxChars?: number, maxEntries?: number, minAgeMs?: number }} [limits]
 * @returns {HtmlCache}
 */
export function htmlPut(c, b, html, now, limits) {
    const lim = limits || {};
    const maxChars = lim.maxChars === undefined ? HTML_MAX_CHARS : lim.maxChars;
    const maxEntries = lim.maxEntries === undefined ? HTML_MAX_ENTRIES : lim.maxEntries;
    const minAge = lim.minAgeMs === undefined ? HTML_MIN_AGE_MS : lim.minAgeMs;
    const k = blockKey(b);
    const kind = b.kind, lang = b.lang || "", text = b.text;
    // Half-written versions of this block: gone, whether the new one is a
    // longer partial or the finished block.
    for (const lk of Array.from(c.live)) {
        if (lk === k) continue;
        const e = c.map.get(lk);
        if (e && e.kind === kind && e.lang === lang && text.length >= e.text.length && text.indexOf(e.text) === 0) drop(c, lk);
    }
    drop(c, k);
    const size = k.length + String(html || "").length;
    c.map.set(k, { html: String(html || ""), kind: kind, lang: lang, text: text, live: !!b.live, size: size, at: now });
    if (b.live) c.live.add(k);
    c.chars += size;
    // Oldest first (a Map iterates in insertion order), never the young.
    if (c.chars > maxChars || c.map.size > maxEntries) {
        // Deleting the entry being visited is safe in a Map's iteration.
        for (const [ok, e] of c.map) {
            if (c.chars <= maxChars && c.map.size <= maxEntries) break;
            if (ok === k || now - e.at < minAge) continue;
            drop(c, ok);
        }
    }
    return c;
}
