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
 * Concise text label for a carousel slide.
 * When only one entry exists and a reset time is known, omit the brand name
 * because the brand icon already sits beside it; when cycling through multiple
 * entries (or when multiple accounts share a provider), include the name.
 *
 * @param {LimitEntry | null | undefined} entry
 * @param {number} total
 * @param {number} now
 * @param {boolean} isResetting
 * @returns {string}
 */
export function slideLabel(entry, total, now, isResetting) {
    if (!entry) return "";
    const left = entry.resetsAt > now ? compactDuration(entry.resetsAt - now) : "";
    const who = entry.account && entry.account.toLowerCase() !== entry.name.toLowerCase()
        ? entry.name + " " + entry.account
        : entry.name;
    if (total <= 1) {
        if (left) return left;
        return isResetting ? "Soon" : entry.name;
    }
    if (left) return who + " · " + left;
    return isResetting ? who + " · soon" : who + " · out";
}

/**
 * Unique brand entries for stacked icon display, active item first.
 * @param {LimitEntry[]} list
 * @param {number} activeIndex
 * @returns {LimitEntry[]}
 */
export function orderedStack(list, activeIndex) {
    if (!list || !list.length) return [];
    const idx = Math.max(0, Math.min(list.length - 1, activeIndex || 0));
    /** @type {LimitEntry[]} */
    const ordered = [list[idx]];
    /** @type {Record<string, boolean>} */
    const seen = {};
    const keyOf = (/** @type {LimitEntry} */ e) => (e.brand || e.id || e.name).toLowerCase();
    seen[keyOf(list[idx])] = true;
    for (let i = 0; i < list.length; i++) {
        if (i === idx) continue;
        const k = keyOf(list[i]);
        if (seen[k]) continue;
        seen[k] = true;
        ordered.push(list[i]);
    }
    return ordered;
}
