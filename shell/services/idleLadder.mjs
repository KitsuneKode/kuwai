export const fadeLead = 15;

/**
 * When the screensaver comes up, in seconds of idleness. As a step of the
 * idle ladder it comes before the fade (which starts fadeLead before the
 * lock) and leaves the lock where it was; under Caffeine, or with no lock,
 * it keeps its own minutes.
 * @param {number} mins  Settings.screensaverMins
 * @param {number} lockAfter  seconds; 0 never locks
 * @param {boolean} held  Caffeine (or another owner of the idle ladder)
 * @returns {number}
 */
export function saverAfter(mins, lockAfter, held) {
    const own = Math.max(1, Number(mins) || 3) * 60;
    if (held || !(lockAfter > 0)) return own;
    const fadeAt = lockAfter > 20 ? lockAfter - fadeLead : lockAfter;
    return Math.max(1, Math.min(own, fadeAt - fadeLead));
}

/**
 * Whether the screensaver is one of the idle ladder's steps right now.
 * @param {string} when  Settings.screensaverWhen
 * @param {boolean} caffeine
 * @returns {boolean}
 */
export function saverAllowed(when, caffeine) {
    const w = when || "always";
    return w === "always" || (w === "caffeine" && !!caffeine);
}

/**
 * "3 min", "4 min 30 s", "45 s".
 * @param {number} seconds
 * @returns {string}
 */
export function afterText(seconds) {
    const s = Math.max(0, Math.round(Number(seconds) || 0));
    if (s < 60) return s + " s";
    return Math.floor(s / 60) + " min" + (s % 60 ? " " + (s % 60) + " s" : "");
}
