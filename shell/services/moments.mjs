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
