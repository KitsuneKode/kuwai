// @ts-check
// Moments' small rules that don't need the shell, so `bun test` can hold
// them (tests/shell/moments.test.mjs). Loaded as written: no build step.

/**
 * What Moments said about calendar events ("Standup · in 10 min", "Now"),
 * minus events that started more than an hour ago. Keys are
 * "<start ms>|<title>|<10|0>". Unchanged input comes back as is (no
 * property change for the shell when there's nothing to forget).
 * @param {Record<string, boolean>} announced
 * @param {number} now  epoch ms
 * @returns {Record<string, boolean>}
 */
export function forgetAnnounced(announced, now) {
    const keep = /** @type {Record<string, boolean>} */ ({});
    let dropped = false;
    for (const k of Object.keys(announced || {})) {
        const start = Number(k.split("|")[0]);
        if (Number.isFinite(start) && start < now - 3600000) dropped = true;
        else keep[k] = announced[k];
    }
    return dropped ? keep : announced;
}

export function nextHideInterval(now, currentInterval, held) {
    if (held || !now) return currentInterval;
    if (now.sticky) return currentInterval;
    return Math.min(currentInterval, 2000);
}

export function dismissMoment(state) {
    return {
        now: null,
        held: false,
        queue: state && Array.isArray(state.queue) ? state.queue : [],
        startGap: !!(state && Array.isArray(state.queue) && state.queue.length > 0)
    };
}

/**
 * What happened while you were away, in one line for the notch, or null when
 * nothing did (then the plain welcome stays). Waiting on you leads.
 * @param {{ waiting: number, done: number, alerts: number }} c
 * @returns {{ label: string, value: string, tone: string, opens: string } | null}
 */
export function awaySummary(c) {
    const w = Math.max(0, c.waiting | 0), d = Math.max(0, c.done | 0), a = Math.max(0, c.alerts | 0);
    if (!w && !d && !a) return null;
    const parts = [];
    if (w) parts.push(w + (w === 1 ? " needs you" : " need you"));
    if (d) parts.push(d + " finished");
    if (a) parts.push(a + (a === 1 ? " alert" : " alerts"));
    return { label: "While you were away", value: parts.join(" · "), tone: w ? "attention" : a ? "caution" : "done", opens: w || d ? "agents" : "center" };
}
