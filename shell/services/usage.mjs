// What the Usage panel says beyond "N % left": whether a limit will run out
// before it resets at the rate it has been spent, and how old a reading is.
//
// The panel used to say "↗ Ahead of pace / On pace / ↘ Under pace" under
// every window. Two of those three are no news, and "ahead of pace" asks the
// reader to work out what it means for them. The one thing worth a line is the
// consequence: "at this rate it runs out in 1h 40m" (with the reset after
// that), said only when it is true.
//
// Plain ES for Qt's engine (no lookbehind, no spread, no named groups), typed
// with JSDoc and checked by tsc (tsconfig.check.json). Quickshell reloads on
// QML changes only: after changing this file, save a QML file too.
// @ts-check

/** A usage window as kuwai-usage reports it. @typedef {{ used: number, resetsAt?: number, durationMins?: number }} UsageWindow */

const MIN = 60000;

/**
 * The share of the window's time already gone (0–1), or -1 when its length or
 * its reset isn't known.
 * @param {UsageWindow} w @param {number} now
 */
export function elapsed(w, now) {
    if (!w || !w.resetsAt || !w.durationMins) return -1;
    const len = w.durationMins * MIN;
    return Math.max(0, Math.min(1, (len - (w.resetsAt - now)) / len));
}

/**
 * Will this limit be spent before it resets, at the average rate so far?
 * null when it won't, when it is already spent, or when there is too little
 * to judge by: the window has barely started (under 10 % of it, or under ten
 * minutes), or almost nothing is used (under 5 %). A burst in the first
 * minutes of a week is not a forecast.
 *
 * Returns how long until it is spent, and how long before the reset that is.
 * Only said when the gap is worth acting on: at least 5 % of the window (15
 * minutes of a 5-hour session, 8 hours of a week).
 * @param {UsageWindow} w @param {number} now
 * @returns {{ inMs: number, earlyMs: number } | null}
 */
export function runsOut(w, now) {
    const e = elapsed(w, now);
    if (e < 0 || !w.resetsAt || !w.durationMins) return null;
    const used = Math.max(0, Math.min(100, Number(w.used) || 0));
    if (used >= 100 || used < 5) return null;
    const len = w.durationMins * MIN, gone = e * len;
    if (e < 0.1 || gone < 10 * MIN) return null;
    const inMs = (100 - used) / (used / gone);
    const earlyMs = w.resetsAt - (now + inMs);
    return earlyMs >= len * 0.05 ? { inMs: inMs, earlyMs: earlyMs } : null;
}

/** "42m", "3h 5m", "2d 4h": the two largest units. @param {number} ms */
export function span(ms) {
    const m = Math.max(0, Math.floor(ms / MIN));
    const d = Math.floor(m / 1440), h = Math.floor(m % 1440 / 60), mm = m % 60;
    return d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + mm + "m" : mm + "m";
}

/**
 * How old a reading is, and whether to say so. Checked in the last half hour:
 * fresh, nothing said. Older: `stale`, its age is shown quietly (T3 Code asks
 * some providers under once an hour, so this is ordinary). Over three hours,
 * or the last view kept from a closed T3 Code ("t3-cached"): `old`, shown as a
 * caution, because the numbers may no longer be true.
 * @param {number | undefined | null} checkedAt @param {number} now @param {string} [source]
 * @returns {{ known: boolean, stale: boolean, old: boolean, age: string }}
 */
export function freshness(checkedAt, now, source) {
    const cached = source === "t3-cached";
    if (!checkedAt) return { known: false, stale: cached, old: cached, age: "" };
    const ms = Math.max(0, now - checkedAt);
    return { known: true, stale: ms > 30 * MIN || cached, old: ms > 180 * MIN || cached, age: ms < MIN ? "just now" : span(ms) + " ago" };
}

/** Where the numbers come from, in words. @param {string} source */
export function sourceName(source) {
    return source === "t3" ? "T3 Code" : source === "t3-cached" ? "T3 Code (closed: its last reading)"
        : source === "kittymux" ? "kittymux" : "";
}
