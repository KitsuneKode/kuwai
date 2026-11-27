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

/**
 * What the saver does once it has been up a long time. The clock on black
 * saves the panel and the power when nothing else will: if the idle ladder's
 * own steps end the saver first (the lock, which ends it, or the screens
 * turning off) it has no step of its own; if the screens turn off before the
 * hour is out, those are the long step and the saver leaves them be.
 * @param {number} mins  Settings.screensaverLongMins; 0 never
 * @param {number} saverAfter  seconds of idleness when the saver comes up
 * @param {number} lockAfter  seconds; 0 never locks
 * @param {number} offAfter  seconds; 0 never turns the screens off
 * @param {boolean} held  Caffeine, a dictation, or another owner of the ladder
 * @returns {{at: number, action: "none"|"clock"|"screens"}}  at: seconds on the saver
 */
export function longIdle(mins, saverAfter, lockAfter, offAfter, held) {
    const at = Math.max(0, Math.round(Number(mins) || 0)) * 60;
    if (!(at > 0)) return { at: 0, action: "none" };
    const up = Math.max(0, Number(saverAfter) || 0);
    const lockIn = !held && lockAfter > 0 ? lockAfter - up : Infinity;
    const offIn = !held && offAfter > 0 ? offAfter - up : Infinity;
    if (offIn <= at && offIn <= lockIn) return { at: Math.max(0, offIn), action: "screens" };
    if (lockIn <= at) return { at: Math.max(0, lockIn), action: "none" };
    return { at, action: "clock" };
}
