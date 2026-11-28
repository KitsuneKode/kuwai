// @ts-check
import { bytes } from "./sizes.mjs";

/** @typedef {{ state: string, id: string, label: string, code: number, result: any, seen: boolean }} Job */

/** @param {unknown} text */
export function parse(text) {
    /** @type {any} */
    let o = null;
    try { o = JSON.parse(String(text || "")); } catch (e) { o = null; }
    const state = o && typeof o.state === "string" ? o.state : "none";
    return {
        state,
        id: o && typeof o.id === "string" ? o.id : "",
        label: o && typeof o.label === "string" ? o.label : "",
        code: o && typeof o.code === "number" ? o.code : -1,
        result: o && o.result && typeof o.result === "object" ? o.result : null,
        seen: !!(o && o.seen),
    };
}

/** @param {Job | null} job */
export function running(job) {
    return !!job && (job.state === "queued" || job.state === "running");
}

/** @param {Job | null} job */
export function unseen(job) {
    return !!job && (job.state === "done" || job.state === "lost") && !job.seen;
}

/**
 * @param {Job} job
 * @param {string} label
 */
export function storageNote(job, label) {
    if (job.state === "lost") return "Clearing " + label + " stopped before it finished";
    const r = job.result || {};
    if (r.ok) return label + " cleared · " + bytes(Number(r.freed) || 0) + " freed";
    return typeof r.why === "string" && r.why ? r.why : "Couldn't clear " + label;
}

/**
 * @param {boolean} putBack
 * @param {string} what
 */
export function cleanupLabel(putBack, what) {
    return (putBack ? "restore:" : "trash:") + what;
}

/** @param {Job} job */
function cleanupParts(job) {
    const i = job.label.indexOf(":");
    return { putBack: job.label.slice(0, i) === "restore", what: job.label.slice(i + 1) };
}

/** @param {Job} job */
export function cleanupBusy(job) {
    const p = cleanupParts(job);
    return p.putBack ? "Putting back…" : "Moving " + p.what + " to the Trash…";
}

/** @param {Job} job */
export function cleanupNote(job) {
    const p = cleanupParts(job);
    if (job.state === "lost") return p.putBack ? "Putting back stopped before it finished" : "Moving " + p.what + " stopped before it finished";
    if (p.putBack) return job.code === 0 ? "Put back" : "Nothing to put back";
    if (job.code !== 0) return "Couldn't move all of " + p.what;
    const kept = job.result && Array.isArray(job.result.unlinked) ? job.result.unlinked.length : 0;
    return "Moved " + p.what + " to the Trash" + (kept ? "; " + kept + " linked from elsewhere: only the links went" : "");
}

/** @param {Job} job */
export function cleanupPutBack(job) {
    return job.state === "done" && job.code === 0 && !cleanupParts(job).putBack;
}
