// @ts-check
import { safeLink } from "./links.mjs";

export const SCHEMA = 1;
export const MAX_BYTES = 65536;
export const MAX_ROWS = 24;
export const MAX_BUCKETS = 8;
export const CRASH_LIMIT = 2;
export const STATES = ["ready", "loading", "empty", "error", "stale", "not_installed", "busy"];
export const TONES = ["neutral", "muted", "info", "good", "warn", "bad"];
export const INTENTS = ["refresh", "openSettings", "openHelp", "copyInstall", "reviewProject", "openUrl"];
export const VISUALS = ["dotBar", "meter"];

const LABELS = {
    refresh: "Scan now",
    openSettings: "Open Settings",
    openHelp: "Learn more",
    copyInstall: "Copy install command",
    reviewProject: "Review",
    openUrl: "Open",
};

const LEN = { id: 64, title: 120, label: 80, value: 32, detail: 240, meta: 64, badge: 32, url: 512, icon: 40, foot: 240 };
const ID = /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/;
const PANEL_ID = /^[a-z][a-z0-9-]{0,31}$/;
const RESERVED_IDS = new Set(["constructor", "prototype", "tostring", "valueof", "hasownproperty", "isprototypeof", "propertyisenumerable", "tolocalestring"]);
/** @param {unknown} id */
function validPanelId(id) { return typeof id === "string" && PANEL_ID.test(id) && !RESERVED_IDS.has(id); }
const ICON = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const CONTROL = /[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/;

/** @typedef {"neutral"|"muted"|"info"|"good"|"warn"|"bad"} Tone */
/** @typedef {{ value: string, label: string, detail: string, tone: Tone }} Hero */
/** @typedef {{ id: string, label: string, value: number, detail: string, tone: Tone }} Bucket */
/** @typedef {{ type: string, total: number, label: string, buckets: Bucket[] }} Visual */
/** @typedef {{ id: string, title: string, detail: string, meta: string, badge: string, actionId: string }} Row */
/** @typedef {{ tone: Tone, title: string, detail: string, actionId: string, actionLabel: string, url: string }} Notice */
/** @typedef {{ icon: string, title: string, detail: string, actionId: string, actionLabel: string, url: string }} Empty */
/** @typedef {{ id: string, label: string, url: string }} Action */
/** @typedef {{ kuwaiPanelSchema: number, id: string, title: string, subtitle: string, state: string, hero: Hero | null, visualization: Visual | null, rowsLabel: string, rows: Row[], notice: Notice | null, empty: Empty | null, primaryAction: Action | null, footnote: string }} Panel */
/** @typedef {{ ok: true, panel: Panel } | { ok: false, error: string, where: string }} Result */

class Refusal extends Error {
    /**
     * @param {string} code
     * @param {string} where
     */
    constructor(code, where) { super(code + " at " + where); this.code = code; this.where = where; }
}

/** @param {string} s */
export function utf8Length(s) {
    let n = 0;
    for (let i = 0; i < s.length; i++) {
        const c = s.charCodeAt(i);
        if (c < 0x80) n += 1;
        else if (c < 0x800) n += 2;
        else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
            const d = s.charCodeAt(i + 1);
            if (d >= 0xdc00 && d <= 0xdfff) { n += 4; i++; } else n += 3;
        } else n += 3;
    }
    return n;
}

/** @param {unknown} v */
function isObject(v) { return !!v && typeof v === "object" && !Array.isArray(v); }

/**
 * @param {any} o
 * @param {string[]} keys
 * @param {string} where
 */
function only(o, keys, where) {
    if (!isObject(o)) throw new Refusal("not_object", where);
    for (const k of Object.keys(o)) if (keys.indexOf(k) < 0) throw new Refusal("unknown_field", where + "." + k);
}

/**
 * @param {any} o
 * @param {string} key
 * @param {number} max
 * @param {string} where
 * @param {boolean} [required]
 */
function text(o, key, max, where, required) {
    const v = o[key];
    if (v === undefined || v === null) {
        if (required) throw new Refusal("missing", where + "." + key);
        return "";
    }
    if (typeof v !== "string") throw new Refusal("not_string", where + "." + key);
    if (v.length > max) throw new Refusal("too_long", where + "." + key);
    if (CONTROL.test(v)) throw new Refusal("control_character", where + "." + key);
    if (required && v.trim() === "") throw new Refusal("missing", where + "." + key);
    return v;
}

/**
 * @param {any} o
 * @param {string} key
 * @param {string} where
 * @returns {Tone}
 */
function tone(o, key, where) {
    const v = o[key];
    if (v === undefined || v === null) return "neutral";
    if (TONES.indexOf(v) < 0) throw new Refusal("bad_tone", where + "." + key);
    return /** @type {Tone} */ (v);
}

/**
 * @param {any} v
 * @param {string} where
 */
function amount(v, where) {
    if (typeof v !== "number" || !isFinite(v) || v < 0 || v > 1e18) throw new Refusal("bad_number", where);
    return v;
}

/**
 * @param {any} o
 * @param {string} where
 * @param {string} [url]
 */
function action(o, where, url) {
    const id = text(o, "actionId", LEN.id, where);
    if (id === "") return "";
    if (INTENTS.indexOf(id) < 0) throw new Refusal("unknown_intent", where + ".actionId");
    if (id === "openUrl" && !safeLink(url)) throw new Refusal("unsafe_url", where + ".url");
    return id;
}

/** @param {any} h */
function hero(h) {
    only(h, ["value", "label", "detail", "tone"], "hero");
    return { value: text(h, "value", LEN.value, "hero", true), label: text(h, "label", LEN.label, "hero"),
        detail: text(h, "detail", LEN.detail, "hero"), tone: tone(h, "tone", "hero") };
}

/** @param {any} v */
function visual(v) {
    only(v, ["type", "total", "label", "buckets"], "visualization");
    if (VISUALS.indexOf(v.type) < 0) throw new Refusal("bad_visualization", "visualization.type");
    if (!Array.isArray(v.buckets) || v.buckets.length < 1) throw new Refusal("missing", "visualization.buckets");
    if (v.buckets.length > MAX_BUCKETS) throw new Refusal("too_many", "visualization.buckets");
    const seen = new Set();
    /** @type {Bucket[]} */
    const buckets = v.buckets.map((/** @type {any} */ b, /** @type {number} */ i) => {
        const at = "visualization.buckets[" + i + "]";
        only(b, ["id", "label", "value", "detail", "tone"], at);
        const id = text(b, "id", LEN.id, at, true);
        if (!ID.test(id) || seen.has(id)) throw new Refusal("bad_id", at + ".id");
        seen.add(id);
        return { id, label: text(b, "label", LEN.label, at, true), value: amount(b.value, at + ".value"),
            detail: text(b, "detail", LEN.detail, at), tone: tone(b, "tone", at) };
    });
    const sum = buckets.reduce((s, b) => s + b.value, 0);
    const total = v.total === undefined ? sum : Math.max(amount(v.total, "visualization.total"), sum);
    return { type: v.type, total, label: text(v, "label", LEN.label, "visualization"), buckets };
}

/** @param {any} rows */
function rowList(rows) {
    if (!Array.isArray(rows)) throw new Refusal("not_array", "rows");
    if (rows.length > MAX_ROWS) throw new Refusal("too_many", "rows");
    const seen = new Set();
    return rows.map((/** @type {any} */ r, /** @type {number} */ i) => {
        const at = "rows[" + i + "]";
        only(r, ["id", "title", "detail", "meta", "badge", "actionId"], at);
        const id = text(r, "id", LEN.id, at, true);
        if (!ID.test(id) || seen.has(id)) throw new Refusal("bad_id", at + ".id");
        seen.add(id);
        const actionId = action(r, at);
        if (actionId === "openUrl") throw new Refusal("unsafe_url", at + ".actionId");
        return { id, title: text(r, "title", LEN.title, at, true), detail: text(r, "detail", LEN.detail, at),
            meta: text(r, "meta", LEN.meta, at), badge: text(r, "badge", LEN.badge, at), actionId };
    });
}

/** @param {any} n */
function notice(n) {
    only(n, ["tone", "title", "detail", "actionId", "actionLabel", "url"], "notice");
    const url = text(n, "url", LEN.url, "notice");
    const actionId = action(n, "notice", url);
    return { tone: tone(n, "tone", "notice"), title: text(n, "title", LEN.title, "notice", true), detail: text(n, "detail", LEN.detail, "notice"),
        actionId, actionLabel: actionId ? text(n, "actionLabel", LEN.label, "notice") || LABELS[/** @type {keyof typeof LABELS} */ (actionId)] : "",
        url: actionId === "openUrl" ? url.trim() : "" };
}

/** @param {any} e */
function empty(e) {
    only(e, ["icon", "title", "detail", "actionId", "actionLabel", "url"], "empty");
    const icon = text(e, "icon", LEN.icon, "empty");
    if (icon && !ICON.test(icon)) throw new Refusal("bad_icon", "empty.icon");
    const url = text(e, "url", LEN.url, "empty");
    const actionId = action(e, "empty", url);
    return { icon, title: text(e, "title", LEN.title, "empty", true), detail: text(e, "detail", LEN.detail, "empty"),
        actionId, actionLabel: actionId ? text(e, "actionLabel", LEN.label, "empty") || LABELS[/** @type {keyof typeof LABELS} */ (actionId)] : "",
        url: actionId === "openUrl" ? url.trim() : "" };
}

/** @param {any} p */
function primary(p) {
    only(p, ["id", "label", "url"], "primaryAction");
    const id = text(p, "id", LEN.id, "primaryAction", true);
    if (INTENTS.indexOf(id) < 0) throw new Refusal("unknown_intent", "primaryAction.id");
    const url = text(p, "url", LEN.url, "primaryAction");
    if (id === "openUrl" && !safeLink(url)) throw new Refusal("unsafe_url", "primaryAction.url");
    return { id, label: text(p, "label", LEN.label, "primaryAction", true), url: id === "openUrl" ? url.trim() : "" };
}

const TOP = ["kuwaiPanelSchema", "id", "title", "subtitle", "state", "hero", "visualization", "rowsLabel", "rows", "notice", "empty", "primaryAction", "footnote"];

/**
 * @param {unknown} o
 * @returns {Result}
 */
export function validate(o) {
    try {
        only(o, TOP, "panel");
        const p = /** @type {any} */ (o);
        if (p.kuwaiPanelSchema !== SCHEMA) throw new Refusal("schema_mismatch", "panel.kuwaiPanelSchema");
        const id = text(p, "id", LEN.id, "panel", true);
        if (!validPanelId(id)) throw new Refusal("bad_id", "panel.id");
        if (STATES.indexOf(p.state) < 0) throw new Refusal("bad_state", "panel.state");
        const has = (/** @type {string} */ k) => p[k] !== undefined && p[k] !== null;
        return { ok: true, panel: {
            kuwaiPanelSchema: SCHEMA, id, state: p.state,
            title: text(p, "title", LEN.title, "panel"), subtitle: text(p, "subtitle", LEN.detail, "panel"),
            hero: has("hero") ? hero(p.hero) : null,
            visualization: has("visualization") ? visual(p.visualization) : null,
            rowsLabel: text(p, "rowsLabel", LEN.label, "panel"),
            rows: has("rows") ? rowList(p.rows) : [],
            notice: has("notice") ? notice(p.notice) : null,
            empty: has("empty") ? empty(p.empty) : null,
            primaryAction: has("primaryAction") ? primary(p.primaryAction) : null,
            footnote: text(p, "footnote", LEN.foot, "panel"),
        } };
    } catch (e) {
        if (e instanceof Refusal) return { ok: false, error: e.code, where: e.where };
        return { ok: false, error: "invalid", where: "panel" };
    }
}

/**
 * @param {unknown} raw
 * @returns {Result}
 */
export function parse(raw) {
    if (typeof raw !== "string") return { ok: false, error: "not_text", where: "input" };
    if (raw.length > MAX_BYTES || utf8Length(raw) > MAX_BYTES) return { ok: false, error: "too_large", where: "input" };
    let o;
    try { o = JSON.parse(raw); } catch (e) { return { ok: false, error: "unreadable", where: "input" }; }
    return validate(o);
}

/**
 * @param {string} id
 * @param {string} title
 * @returns {Panel}
 */
export function brokenPanel(id, title) {
    return { kuwaiPanelSchema: SCHEMA, id: PANEL_ID.test(id) ? id : "panel", title: String(title || "").slice(0, LEN.title), subtitle: "",
        state: "error", hero: null, visualization: null, rowsLabel: "", rows: [], empty: null, primaryAction: null, footnote: "",
        notice: { tone: "bad", title: "This panel can't be shown", detail: "What it sent isn't something kuwai can draw. Updating it may help.",
            actionId: "refresh", actionLabel: "Try again", url: "" } };
}

/**
 * @param {unknown} id
 * @param {unknown} [url]
 * @returns {{ intent: string, url: string } | null}
 */
export function intentOf(id, url) {
    if (typeof id !== "string" || INTENTS.indexOf(id) < 0) return null;
    if (id === "openUrl") return safeLink(url) ? { intent: id, url: String(url).trim() } : null;
    return { intent: id, url: "" };
}

/** @param {unknown} base */
function cleanBase(base) {
    const b = String(base || "");
    if (!b.startsWith("/") || CONTROL.test(b) || b.split("/").some(p => p === ".." || p === ".")) return "";
    return b.replace(/\/+$/, "");
}

/**
 * @param {unknown} cacheHome
 * @param {unknown} id
 */
export function cacheDir(cacheHome, id) {
    const base = cleanBase(cacheHome);
    if (!base || typeof id !== "string" || !PANEL_ID.test(id)) return "";
    return base + "/kuwai/panels/" + id;
}

/**
 * @param {unknown} cacheHome
 * @param {unknown} id
 * @param {unknown} name
 */
export function cacheFile(cacheHome, id, name) {
    const dir = cacheDir(cacheHome, id);
    if (!dir || typeof name !== "string" || !/^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/.test(name) || name.indexOf("..") >= 0) return "";
    return dir + "/" + name;
}

/** @param {string} path */
export function statArgv(path) {
    return ["stat", "--format=%F|%s|%u|%h", "--", path];
}

/**
 * @param {unknown} out
 * @param {number} [uid]
 */
export function cacheEntryOk(out, uid) {
    const parts = String(out || "").trim().split("|");
    if (parts.length !== 4) return false;
    const size = Number(parts[1]), owner = Number(parts[2]), links = Number(parts[3]);
    if (parts[0] !== "regular file" && parts[0] !== "regular empty file") return false;
    if (!(size >= 0 && size <= MAX_BYTES) || links !== 1) return false;
    return uid === undefined || owner === uid;
}

/** @param {unknown} stateHome */
export function healthPath(stateHome) {
    const base = cleanBase(stateHome);
    return base ? base + "/kuwai/panel-health.json" : "";
}

/** @typedef {{ crashes: number, quarantined: boolean, at: number }} Health */
/** @typedef {{ version: number, panels: Object<string, Health> }} HealthBook */

/**
 * @param {unknown} raw
 * @returns {HealthBook}
 */
export function parseHealth(raw) {
    /** @type {HealthBook} */
    const book = { version: 1, panels: Object.create(null) };
    let o;
    try { o = typeof raw === "string" && raw.length <= MAX_BYTES ? JSON.parse(raw) : null; } catch (e) { o = null; }
    if (!isObject(o) || !isObject(o.panels)) return book;
    for (const id of Object.keys(o.panels).slice(0, 64)) {
        const h = o.panels[id];
        if (!validPanelId(id) || !isObject(h)) continue;
        const crashes = Math.max(0, Math.min(99, Math.floor(Number(h.crashes) || 0)));
        book.panels[id] = { crashes, quarantined: h.quarantined === true || crashes >= CRASH_LIMIT, at: Number(h.at) > 0 ? Number(h.at) : 0 };
    }
    return book;
}

/**
 * @param {HealthBook} book
 * @param {string} id
 * @param {Health} next
 * @returns {HealthBook}
 */
function withPanel(book, id, next) {
    /** @type {Object<string, Health>} */
    const panels = Object.create(null);
    for (const k of Object.keys(book.panels)) if (validPanelId(k)) panels[k] = book.panels[k];
    panels[id] = next;
    return { version: 1, panels };
}

/** @param {HealthBook} book @param {string} id */
function panelHealth(book, id) {
    return validPanelId(id) && Object.prototype.hasOwnProperty.call(book.panels, id) ? book.panels[id] : undefined;
}

/**
 * @param {HealthBook} book
 * @param {string} id
 * @param {number} now
 */
export function noteCrash(book, id, now) {
    if (!validPanelId(id)) return book;
    const was = panelHealth(book, id) || { crashes: 0, quarantined: false, at: 0 };
    const crashes = Math.min(99, was.crashes + 1);
    return withPanel(book, id, { crashes, quarantined: was.quarantined || crashes >= CRASH_LIMIT, at: now });
}

/**
 * @param {HealthBook} book
 * @param {string} id
 */
export function noteHealthy(book, id) {
    const was = panelHealth(book, id);
    if (!was || was.quarantined || was.crashes === 0) return book;
    return withPanel(book, id, { crashes: 0, quarantined: false, at: was.at });
}

/**
 * @param {HealthBook} book
 * @param {string} id
 */
export function release(book, id) {
    const was = panelHealth(book, id);
    if (!was) return book;
    return withPanel(book, id, { crashes: 0, quarantined: false, at: was.at });
}

/**
 * @param {HealthBook} book
 * @param {string} id
 * @param {Object<string, string | undefined>} env
 */
export function allowed(book, id, env) {
    if (env && env.KUWAI_NO_PLUGINS === "1") return false;
    if (!validPanelId(id)) return false;
    const h = panelHealth(book, id);
    return !(h && h.quarantined);
}

/** @param {HealthBook} book */
export function healthText(book) {
    return JSON.stringify(book) + "\n";
}

/**
 * @param {number[]} values
 * @param {number} total
 * @param {number} cells
 * @returns {number[]}
 */
export function dotCounts(values, total, cells) {
    const n = Math.max(0, Math.floor(cells));
    const v = values.map(x => (typeof x === "number" && isFinite(x) && x > 0 ? x : 0));
    const sum = v.reduce((a, b) => a + b, 0);
    const whole = Math.max(sum, typeof total === "number" && isFinite(total) ? total : 0);
    if (!n || !(whole > 0)) return v.map(() => 0);
    const exact = v.map(x => x / whole * n);
    const out = exact.map(x => Math.floor(x));
    const lit = v.filter(x => x > 0).length;
    let room = Math.min(n, Math.round(sum / whole * n)) - out.reduce((a, b) => a + b, 0);
    const order = exact.map((x, i) => i).sort((a, b) => (exact[b] - out[b]) - (exact[a] - out[a]));
    for (const i of order) { if (room <= 0) break; if (v[i] > 0) { out[i]++; room--; } }
    if (lit <= n) for (let i = 0; i < out.length; i++) {
        if (v[i] > 0 && out[i] === 0) {
            let big = -1;
            for (let j = 0; j < out.length; j++) if (out[j] > 1 && (big < 0 || out[j] > out[big])) big = j;
            if (big >= 0) { out[big]--; out[i] = 1; } else if (out.reduce((a, b) => a + b, 0) < n) out[i] = 1;
        }
    }
    return out;
}

/**
 * @param {number[]} counts
 * @param {number} cells
 * @returns {number[]}
 */
export function dotOwners(counts, cells) {
    const out = new Array(Math.max(0, Math.floor(cells))).fill(-1);
    let at = 0;
    for (let i = 0; i < counts.length; i++) for (let k = 0; k < counts[i] && at < out.length; k++) out[at++] = i;
    return out;
}
