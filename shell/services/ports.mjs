// @ts-check
import { bytes as sizeText } from "./sizes.mjs";
import { diff as listDiff } from "./activity.mjs";

export const BEAT = 5;

/** @typedef {{port: number, host: string, proc: string, what: string, project: string, pid: number, start: number, age: number, agent: string, parentApp: string, memBytes: number, cpu: number, local: boolean, key: string, title: string, monogram: string, scope: string, memText: string, sub: string, openable: boolean}} PortRow */
/** @typedef {{keys: string[], rows: Record<string, PortRow>, seq: number}} PortSnap */

/**
 * @param {string[]} from
 * @param {string[]} to
 * @returns {{op: "remove" | "move" | "insert", at?: number, from?: number, to?: number, key?: string}[]}
 */
export function diff(from, to) { return listDiff(from, to); }

/** @param {unknown} v */
function text(v) { return typeof v === "string" ? v : ""; }

/** @param {unknown} v */
function num(v) {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
}

/** @param {{pid: number, start: number}} r */
export function keyOf(r) { return r.pid + ":" + r.start; }

/** @param {string} host */
export function scopeOf(host) {
    const h = host.trim().toLowerCase();
    return h === "::1" || h.startsWith("127.") ? "local" : "lan";
}

/** @param {string} host */
export function openable(host) {
    const h = host.trim().toLowerCase();
    return h === "::" || h === "0.0.0.0" || h === "::1" || h.startsWith("127.");
}

/**
 * @param {string} what
 * @param {string} proc
 */
export function monogram(what, proc) {
    const s = (what + " " + proc).toLowerCase();
    if (/\bnext\b/.test(s)) return "NX";
    if (/\bvite\b/.test(s)) return "VT";
    if (/\bastro\b/.test(s)) return "AS";
    if (/\bbun\b/.test(s)) return "BN";
    if (/python|uvicorn|flask|django/.test(s)) return "PY";
    if (/postgres/.test(s)) return "PG";
    if (/redis/.test(s)) return "RD";
    if (/docker/.test(s)) return "DK";
    const letters = (what || proc).replace(/[^a-z0-9]/gi, "").toUpperCase();
    return letters.slice(0, 2) || "··";
}

/** @param {unknown} age seconds */
export function ageText(age) {
    const s = Math.max(0, num(age));
    if (s < 60) return "now";
    const m = Math.floor(s / 60);
    if (m < 60) return m + "m";
    const h = Math.floor(m / 60);
    if (h < 24) return h + "h";
    return Math.floor(h / 24) + "d";
}

/** @param {PortRow} r */
export function subline(r) {
    const parts = [];
    if (r.what && r.what !== r.title) parts.push(r.what);
    if (r.agent) parts.push(r.agent);
    if (r.parentApp) parts.push("inside " + r.parentApp);
    parts.push(ageText(r.age));
    return parts.join(" · ");
}

/** @param {any} raw */
function row(raw) {
    if (!raw || typeof raw !== "object") return null;
    const pid = Math.trunc(num(raw.pid));
    const start = Math.trunc(num(raw.start));
    const port = Math.trunc(num(raw.port));
    if (!(pid > 0) || !(start >= 0) || !(port > 0)) return null;
    const host = text(raw.host);
    const proc = text(raw.proc);
    const what = text(raw.what) || proc;
    const project = text(raw.project);
    /** @type {PortRow} */
    const r = {
        port, host, proc, what, project, pid, start,
        age: Math.max(0, num(raw.age)), agent: text(raw.agent), parentApp: text(raw.parentApp),
        memBytes: Math.max(0, num(raw.memBytes)), cpu: Math.max(0, num(raw.cpu)), local: !!raw.local,
        key: keyOf({ pid, start }), title: project || what || proc,
        monogram: monogram(what, proc), scope: scopeOf(host), memText: sizeText(num(raw.memBytes)),
        sub: "", openable: openable(host)
    };
    r.sub = subline(r);
    return r;
}

/**
 * @param {string} textOut the helper's whole JSON answer
 * @returns {PortRow[] | null}
 */
export function parseRows(textOut) {
    let v;
    try { v = JSON.parse(textOut); } catch (e) { return null; }
    if (!Array.isArray(v)) return null;
    /** @type {PortRow[]} */
    const rows = [];
    for (const raw of v) {
        const r = row(raw);
        if (r) rows.push(r);
    }
    return rows;
}

/**
 * @param {PortRow} a
 * @param {PortRow} b
 * @param {string} key
 * @param {number} dir
 */
export function compare(a, b, key, dir) {
    let d = 0;
    if (key === "cpu") d = a.cpu - b.cpu;
    else if (key === "memory") d = a.memBytes - b.memBytes;
    else d = a.port - b.port;
    if (d !== 0) return d * dir;
    const ta = a.title.toLowerCase(), tb = b.title.toLowerCase();
    if (ta !== tb) return ta < tb ? -1 : 1;
    return a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
}

/**
 * @param {PortRow[]} rows
 * @param {string} key
 * @param {number} dir
 */
export function sortRows(rows, key, dir) {
    return rows.slice().sort((a, b) => compare(a, b, key, dir));
}

/** @returns {PortSnap} */
export function empty() { return { keys: [], rows: {}, seq: 0 }; }

/** @param {PortSnap} prev */
export function resort(prev) { return { keys: [], rows: prev.rows, seq: 0 }; }

/**
 * Rows are re-sorted on the same slow beat as Activity, or when the sort changed; a hovered,
 * keyboard-held or armed row keeps its place meanwhile.
 * @param {PortSnap} prev
 * @param {PortRow[]} incoming
 * @param {{sortKey?: string, sortDir?: number, freeze?: boolean}} [opts]
 * @returns {PortSnap}
 */
export function step(prev, incoming, opts) {
    const sortKey = opts && opts.sortKey || "port";
    const sortDir = opts && opts.sortDir || 1;
    const freeze = !!(opts && opts.freeze);
    /** @type {Record<string, PortRow>} */
    const rows = {};
    for (const r of incoming) rows[r.key] = r;
    const keysIn = Object.keys(rows);
    const bySort = (/** @type {string} */ a, /** @type {string} */ b) => compare(rows[a], rows[b], sortKey, sortDir);
    const reorder = prev.keys.length === 0 || (prev.seq % BEAT === 0 && !freeze);
    let keys;
    if (reorder) keys = keysIn.sort(bySort);
    else {
        const kept = prev.keys.filter(k => rows[k]);
        const fresh = keysIn.filter(k => !prev.rows[k]).sort(bySort);
        keys = kept.concat(fresh);
    }
    return { keys, rows, seq: prev.seq + 1 };
}

/** @param {{failed: boolean, ready: boolean, count: number}} s @returns {"error" | "loading" | "empty" | "ready"} */
export function phase(s) {
    if (s.failed) return "error";
    if (!s.ready) return "loading";
    return s.count === 0 ? "empty" : "ready";
}

/** @returns {{key: string, action: string}} */
export function nothingArmed() { return { key: "", action: "" }; }

/**
 * Every destructive action arms first; the same press again fires it.
 * @param {{key: string, action: string}} armed
 * @param {string} key
 * @param {"stop" | "force"} action
 * @returns {{armed: {key: string, action: string}, fire: boolean}}
 */
export function press(armed, key, action) {
    if (armed.key === key && armed.action === action) return { armed: nothingArmed(), fire: true };
    return { armed: { key, action }, fire: false };
}

/** @param {{key: string, action: string}} armed @param {string[]} keys */
export function keepArmed(armed, keys) { return keys.indexOf(armed.key) >= 0 ? armed : nothingArmed(); }

/** @param {{ok?: boolean, gone?: boolean, why?: string}} r @param {string} name */
export function outcome(r, name) {
    if (r && r.ok && r.gone === false) return "Still running";
    if (r && r.ok) return "";
    return "Couldn't stop " + name + (r && r.why ? ": " + r.why : "");
}

/** @param {string} note */
export function noteWarns(note) { return note.indexOf("Still") === 0 || note.indexOf("Couldn't") === 0; }
