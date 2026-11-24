// @ts-check

/**
 * A single limit item shown in the right-side island limit carousels.
 * @typedef {{ key: string, id: string, brand: string, tint: string, name: string, account: string, resetsAt: number, windowLabel: string, source: string }} LimitEntry
 */

/**
 * Compact duration string ("3d", "15h", "42m", "1m").
 * @param {number} ms
 * @returns {string}
 */
export function compactDuration(ms) {
    if (!isFinite(ms) || ms <= 0) return "";
    const d = Math.floor(ms / 86400000);
    const h = Math.floor(ms / 3600000);
    const m = Math.max(1, Math.ceil(ms / 60000));
    return d > 0 ? d + "d" : h > 0 ? h + "h" : m + "m";
}

/**
 * Partition exhausted quota entries (and any extra session-reported limits) into
 * two disjoint, deduplicated lists for the right-side island pills:
 *   - resettingSoon: resetsAt in (now, now + soonMs], soonest first
 *   - exhaustedLater: resetsAt > now + soonMs or unknown (0), soonest first
 *
 * Deduplicates by provider+account (keeping the soonest known reset). If an
 * agent session reports a limit for a provider that already has a quota entry,
 * the richer quota entry wins.
 *
 * @param {LimitEntry[]} quotaExhausted
 * @param {LimitEntry[]} sessionLimited
 * @param {number} now
 * @param {number} soonMs
 * @returns {{ resettingSoon: LimitEntry[], exhaustedLater: LimitEntry[] }}
 */
export function partitionLimits(quotaExhausted, sessionLimited, now, soonMs) {
    /** @type {Record<string, LimitEntry>} */
    const byKey = {};
    /** @type {Record<string, boolean>} */
    const quotaProviders = {};

    for (const x of quotaExhausted || []) {
        if (!x || !x.name) continue;
        const r = Number(x.resetsAt || 0);
        if (r > 0 && r <= now) continue;
        const pid = String(x.id || x.name).toLowerCase();
        quotaProviders[pid] = true;
        const dedup = pid + "|" + String(x.account || "").toLowerCase();
        const prev = byKey[dedup];
        const prevR = prev && prev.resetsAt > 0 ? prev.resetsAt : Infinity;
        const nextR = r > 0 ? r : Infinity;
        if (!prev || nextR < prevR) {
            byKey[dedup] = {
                key: x.key || dedup,
                id: x.id || pid,
                brand: x.brand || "",
                tint: x.tint || "",
                name: x.name,
                account: x.account || "",
                resetsAt: r,
                windowLabel: x.windowLabel || "",
                source: x.source || "quota"
            };
        }
    }

    for (const x of sessionLimited || []) {
        if (!x || !x.name) continue;
        const r = Number(x.resetsAt || 0);
        if (r > 0 && r <= now) continue;
        const pid = String(x.id || x.name).toLowerCase();
        if (quotaProviders[pid]) continue;
        const dedup = pid + "|" + String(x.account || "").toLowerCase();
        const prev = byKey[dedup];
        const prevR = prev && prev.resetsAt > 0 ? prev.resetsAt : Infinity;
        const nextR = r > 0 ? r : Infinity;
        if (!prev || nextR < prevR) {
            byKey[dedup] = {
                key: x.key || dedup,
                id: x.id || pid,
                brand: x.brand || "",
                tint: x.tint || "",
                name: x.name,
                account: x.account || "",
                resetsAt: r,
                windowLabel: x.windowLabel || "",
                source: x.source || "agent"
            };
        }
    }

    /** @type {LimitEntry[]} */
    const resettingSoon = [];
    /** @type {LimitEntry[]} */
    const exhaustedLater = [];
    const windowMs = soonMs > 0 ? soonMs : 15 * 60000;

    for (const k of Object.keys(byKey)) {
        const entry = byKey[k];
        if (entry.resetsAt > now && entry.resetsAt - now <= windowMs) {
            resettingSoon.push(entry);
        } else {
            exhaustedLater.push(entry);
        }
    }

    /** @param {LimitEntry} a @param {LimitEntry} b */
    const cmp = (a, b) => {
        const ar = a.resetsAt > now ? a.resetsAt : Infinity;
        const br = b.resetsAt > now ? b.resetsAt : Infinity;
        return (ar - br) || a.name.localeCompare(b.name);
    };
    resettingSoon.sort(cmp);
    exhaustedLater.sort(cmp);
    return { resettingSoon, exhaustedLater };
}

/**
 * One capsule's worth: when you can carry on (the soonest known reset), whether
 * that is within the soon window, and each provider once with how many of its
 * accounts are out.
 * @param {{ resettingSoon: LimitEntry[], exhaustedLater: LimitEntry[] }} part
 * @param {number} now
 * @returns {{ tone: string, label: string, at: number, providers: { id: string, brand: string, tint: string, name: string, count: number }[], items: LimitEntry[] }}
 */
export function summarizeLimits(part, now) {
    const items = [...(part && part.resettingSoon || []), ...(part && part.exhaustedLater || [])];
    if (!items.length) return { tone: "", label: "", at: 0, providers: [], items: [] };
    const at = items.reduce((m, e) => e.resetsAt > now && (!m || e.resetsAt < m) ? e.resetsAt : m, 0);
    /** @type {Record<string, { id: string, brand: string, tint: string, name: string, count: number }>} */
    const by = {};
    /** @type {{ id: string, brand: string, tint: string, name: string, count: number }[]} */
    const providers = [];
    for (const e of items) {
        const k = String(e.id || e.name).toLowerCase();
        if (!by[k]) providers.push(by[k] = { id: e.id, brand: e.brand, tint: e.tint, name: e.name, count: 0 });
        by[k].count++;
    }
    return {
        tone: part.resettingSoon.length ? "soon" : "out",
        label: at ? compactDuration(at - now) : "Out",
        at, providers, items
    };
}
