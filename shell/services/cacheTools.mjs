// @ts-check

/** @typedef {{ id: string, label: string, bytes: number, command: string, runnable: boolean, note: string }} Part */

export const RUNNABLE = ["docker-images", "docker-builder"];

/** @param {unknown} n */
function whole(n) {
    const v = Number(n);
    return isFinite(v) && v > 0 ? v : 0;
}

/**
 * @param {{ parts?: any } | null | undefined} item
 * @returns {Part[]}
 */
export function partRows(item) {
    const parts = item && item.parts && typeof item.parts !== "string" && typeof item.parts.length === "number" ? item.parts : [];
    const rows = [];
    for (let i = 0; i < parts.length; i++) {
        const p = parts[i];
        if (!p || typeof p.id !== "string" || typeof p.command !== "string" || p.command === "") continue;
        rows.push({
            id: p.id,
            label: String(p.label || p.id),
            bytes: whole(p.bytes),
            command: p.command,
            runnable: p.runnable === true && RUNNABLE.indexOf(p.id) >= 0,
            note: typeof p.note === "string" ? p.note : "",
        });
    }
    return rows;
}

/** @param {{ docker?: { state?: string } } | null | undefined} report */
export function unavailable(report) {
    const state = report && report.docker ? report.docker.state : "";
    if (state === "down") return "Docker isn't running, so what it holds isn't counted";
    if (state === "denied") return "Docker won't talk to this user (it needs the docker group), so what it holds isn't counted";
    return "";
}

/** @param {{ clearable?: boolean, bytes?: unknown }[]} items */
export function clearableBytes(items) {
    let n = 0;
    for (const i of items || []) if (i && i.clearable === true) n += whole(i.bytes);
    return n;
}
