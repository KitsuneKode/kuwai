/**
 * The order the photos come in: a shuffle that is the same for the same seed.
 * @param {number} count  how many pictures
 * @param {number} seed  any integer
 * @returns {number[]}  every index below count, once
 */
export function order(count, seed) {
    const n = Math.max(0, Math.floor(Number(count) || 0));
    const out = [];
    for (let i = 0; i < n; i++) out.push(i);
    let a = (Math.floor(Number(seed) || 0) >>> 0) || 1;
    const next = () => {
        a = (a + 0x6D2B79F5) >>> 0;
        let t = a;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    for (let i = n - 1; i > 0; i--) {
        const j = Math.floor(next() * (i + 1));
        const x = out[i]; out[i] = out[j]; out[j] = x;
    }
    return out;
}

/**
 * How long each photo stays, in milliseconds.
 * @param {number} mins  Settings.screensaverPhotoMins
 * @returns {number}
 */
export function holdMs(mins) {
    const m = Math.round(Number(mins));
    return Math.min(120, Math.max(1, m > 0 ? m : 5)) * 60000;
}

/**
 * A file's URL: a name with a # or ? in it is still the file.
 * @param {string} path
 * @returns {string}
 */
export function fileUrl(path) {
    const p = String(path || "");
    if (p === "") return "";
    return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F");
}

/**
 * The size a picture is decoded at: the screen's longer side, in a square the
 * picture fits within, never past what a picture on the saver gains from.
 * @param {number} width
 * @param {number} height
 * @param {number} cap
 * @returns {number}
 */
export function decodeSide(width, height, cap) {
    const w = Math.max(0, Number(width) || 0), h = Math.max(0, Number(height) || 0);
    return Math.min(Math.max(Math.round(Math.max(w, h)), 1), Math.max(1, Number(cap) || 2560));
}

/**
 * The one after this, skipping what failed to decode.
 * @param {number} at  index in the order now showing
 * @param {number} count
 * @param {Object<number, boolean>} bad  indices (in the order) that did not load
 * @returns {number}  -1 when nothing else can be shown
 */
export function after(at, count, bad) {
    for (let step = 1; step <= count; step++) {
        const i = (at + step) % count;
        if (i === at) return -1;
        if (!(bad && bad[i])) return i;
    }
    return -1;
}
