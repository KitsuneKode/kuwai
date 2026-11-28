// @ts-check

export const KB = 1e3;
export const MB = 1e6;
export const GB = 1e9;
export const TB = 1e12;

const UNITS = ["B", "kB", "MB", "GB", "TB"];

/** @param {unknown} n */
function whole(n) {
    const v = Number(n);
    return isFinite(v) && v > 0 ? v : 0;
}

/**
 * Decimal, the way GNOME and macOS print sizes: 1 kB is 1000 B.
 * Gigabytes and up keep one decimal below `wholeFrom`.
 * @param {unknown} n bytes
 * @param {number} [wholeFrom]
 */
export function bytes(n, wholeFrom = 10) {
    let v = whole(n);
    let i = 0;
    while (i < UNITS.length - 1 && v >= 1000) { v /= 1000; i++; }
    if (i === 0) return Math.round(v) + " B";
    let digits = i >= 3 && v < wholeFrom ? 1 : 0;
    let text = v.toFixed(digits);
    if (Number(text) >= 1000 && i < UNITS.length - 1) { v /= 1000; i++; digits = i >= 3 && v < wholeFrom ? 1 : 0; text = v.toFixed(digits); }
    return text.replace(/\.0$/, "") + " " + UNITS[i];
}

/** @param {unknown} n bytes */
export function compact(n) {
    const b = whole(n);
    if (b >= 10 * GB) return Math.round(b / GB) + "G";
    if (b >= GB) return (Math.round(b / GB * 10) / 10) + "G";
    return Math.max(1, Math.round(b / MB)) + "M";
}

/** @param {unknown} n bytes */
export function inGB(n) {
    return whole(n) / GB;
}

/** @param {unknown} n kibibytes, as /proc/meminfo and ps count */
export function fromKiB(n) {
    return whole(n) * 1024;
}

/** @param {unknown} n mebibytes, as nvidia-smi and ps report */
export function fromMiB(n) {
    return whole(n) * 1048576;
}
