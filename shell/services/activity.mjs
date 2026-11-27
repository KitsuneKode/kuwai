// @ts-check

export const BEAT = 5;

/**
 * @param {string} line one line of what bin/kuwai-activity streams
 * @returns {{cpus: number, units: any[]} | null}
 */
export function parseFrame(line) {
    let v;
    try { v = JSON.parse(line); } catch (e) { return null; }
    if (!v || typeof v !== "object" || !Array.isArray(v.units)) return null;
    const units = [];
    for (const u of v.units) {
        if (!u || typeof u.unit !== "string" || u.unit === "") continue;
        units.push({
            key: u.unit,
            unit: u.unit,
            id: String(u.id || ""),
            launcher: String(u.launcher || ""),
            label: String(u.label || u.main || u.id || u.unit),
            main: String(u.main || ""),
            pid: Number(u.pid) || 0,
            start: Number(u.start) || 0,
            procs: Math.max(1, Number(u.procs) || 1),
            cpu: Math.max(0, Number(u.cpu) || 0),
            mem: u.mem === null || u.mem === undefined ? -1 : Math.max(0, Number(u.mem) || 0),
            protected: !!u.protected
        });
    }
    return { cpus: Math.max(1, Number(v.cpus) || 1), units };
}

/**
 * Busiest first by the whole percent that is shown, then the larger memory, then by name.
 * @param {{cpu: number, mem: number, label: string, key: string}} a
 * @param {{cpu: number, mem: number, label: string, key: string}} b
 */
export function rank(a, b) {
    const ca = Math.round(a.cpu), cb = Math.round(b.cpu);
    if (ca !== cb) return cb - ca;
    if (a.mem !== b.mem) return b.mem - a.mem;
    const la = a.label.toLowerCase(), lb = b.label.toLowerCase();
    if (la !== lb) return la < lb ? -1 : 1;
    return a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
}

/** @returns {{keys: string[], rows: Record<string, any>, seq: number, cpus: number}} */
export function empty() {
    return { keys: [], rows: {}, seq: 0, cpus: 1 };
}

/**
 * The next list from a frame. Rows are re-sorted on the slow beat (every BEAT frames, the
 * beat memory is read on) and when the list was empty; in between they keep their places,
 * newcomers at the end, so a row does not run from under the pointer. `freeze` (a row is
 * hovered or armed) holds the places on the beat too.
 * @param {{keys: string[], rows: Record<string, any>, seq: number}} prev
 * @param {{cpus: number, units: any[]}} frame
 * @param {{freeze?: boolean}} [opts]
 */
export function step(prev, frame, opts) {
    const freeze = !!(opts && opts.freeze);
    /** @type {Record<string, any>} */
    const rows = {};
    for (const u of frame.units) rows[u.key] = u;
    const incoming = Object.keys(rows);
    const byRank = (/** @type {string} */ a, /** @type {string} */ b) => rank(rows[a], rows[b]);
    const resort = prev.keys.length === 0 || (prev.seq % BEAT === 0 && !freeze);
    let keys;
    if (resort) keys = incoming.sort(byRank);
    else {
        const kept = prev.keys.filter(k => rows[k]);
        const fresh = incoming.filter(k => !prev.rows[k]).sort(byRank);
        keys = kept.concat(fresh);
    }
    return { keys, rows, seq: prev.seq + 1, cpus: frame.cpus };
}

/**
 * The edits that turn the list `from` into `to`, in order, for a ListModel.
 * @param {string[]} from
 * @param {string[]} to
 * @returns {{op: "remove" | "move" | "insert", at?: number, from?: number, to?: number, key?: string}[]}
 */
export function diff(from, to) {
    const ops = [];
    const work = from.slice();
    const want = new Set(to);
    for (let i = work.length - 1; i >= 0; i--) {
        if (!want.has(work[i])) { ops.push({ op: "remove", at: i }); work.splice(i, 1); }
    }
    for (let i = 0; i < to.length; i++) {
        if (work[i] === to[i]) continue;
        const j = work.indexOf(to[i], i);
        if (j >= 0) {
            ops.push({ op: "move", from: j, to: i });
            work.splice(i, 0, work.splice(j, 1)[0]);
        } else {
            ops.push({ op: "insert", at: i, key: to[i] });
            work.splice(i, 0, to[i]);
        }
    }
    return ops;
}

/** @param {number} cpu percent of one logical CPU */
export function cpuText(cpu) {
    const n = Math.round(cpu);
    return n + "%";
}

/** @param {number} bytes -1 when it could not be read */
export function memText(bytes) {
    if (bytes < 0) return "";
    if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(bytes >= 10737418240 ? 0 : 1) + " GB";
    if (bytes >= 1048576) return Math.round(bytes / 1048576) + " MB";
    return Math.max(1, Math.round(bytes / 1024)) + " KB";
}

/**
 * How hard it works the machine: the share of every thread it takes (the cores' own bars turn
 * orange past 70 % and red past 90 %).
 * @param {number} cpu percent of one logical CPU
 * @param {number} cpus logical CPUs
 * @returns {"" | "orange" | "red"}
 */
export function cpuTone(cpu, cpus) {
    const share = cpu / (100 * Math.max(1, cpus));
    return share > 0.9 ? "red" : share > 0.7 ? "orange" : "";
}

/** @param {{procs: number}} r */
export function detail(r) {
    return r.procs === 1 ? "1 process" : r.procs + " processes";
}

/** @returns {{key: string, action: string}} */
export function nothingArmed() { return { key: "", action: "" }; }

/**
 * A press on Stop or Force quit. Stop acts at once; Force quit takes two presses on the same
 * row (the first arms it, the next fires), and pressing another row arms that one instead.
 * @param {{key: string, action: string}} armed
 * @param {string} key
 * @param {"stop" | "force"} action
 * @returns {{armed: {key: string, action: string}, fire: boolean}}
 */
export function press(armed, key, action) {
    if (action === "stop") return { armed: nothingArmed(), fire: true };
    if (armed.key === key && armed.action === "force") return { armed: nothingArmed(), fire: true };
    return { armed: { key, action: "force" }, fire: false };
}

/**
 * What is armed once the list changed: a row that left takes its arming with it.
 * @param {{key: string, action: string}} armed
 * @param {string[]} keys
 */
export function keepArmed(armed, keys) {
    return keys.indexOf(armed.key) >= 0 ? armed : nothingArmed();
}

/**
 * Which of the tab's four faces to show.
 * @param {{failed: boolean, ready: boolean, count: number}} s
 * @returns {"error" | "loading" | "empty" | "list"}
 */
export function viewState(s) {
    if (s.failed) return "error";
    if (!s.ready) return "loading";
    return s.count === 0 ? "empty" : "list";
}

/**
 * A note under a row after Stop or Force quit answered.
 * @param {{ok?: boolean, gone?: boolean, why?: string}} r
 * @param {string} name
 */
export function outcome(r, name) {
    if (r && r.ok && r.gone === false) return "Still running. Force quit ends it.";
    if (r && r.ok) return "";
    return "Couldn't stop " + name + (r && r.why ? ": " + r.why : "");
}

/** @param {string} note a row's note after an answer */
export function noteWarns(note) {
    return note.indexOf("Still") === 0 || note.indexOf("Couldn't") === 0;
}
