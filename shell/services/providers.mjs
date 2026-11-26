// @ts-check

/**
 * @typedef {{ id: string, driver?: string, name?: string, accent?: string, enabled?: boolean | null, status: string,
 *   reason?: string, auth?: string, plan?: string, models?: string[][] }} Provider
 * @typedef {{ state: string, list: Provider[] }} Reading
 */

const STATES = ["ok", "none", "unavailable"];
const STATUSES = ["ready", "warning", "error", "disabled", "unavailable"];
const PENDING = /\bnot (?:been )?checked\b/i;

/** @param {unknown} v @param {number} cap @returns {string} */
function str(v, cap) {
    return typeof v === "string" ? v.slice(0, cap) : "";
}

/** @param {any} p @returns {Provider | null} */
function clean(p) {
    if (!p || typeof p !== "object" || typeof p.id !== "string" || !p.id) return null;
    const status = STATUSES.indexOf(p.status) >= 0 ? p.status : "unavailable";
    if (status === "unavailable") return { id: str(p.id, 96), status: status };
    const models = Array.isArray(p.models)
        ? p.models.filter(/** @param {any} m */ m => Array.isArray(m) && typeof m[0] === "string" && typeof m[1] === "string")
            .map(/** @param {string[]} m */ m => [m[0], m[1]])
        : [];
    return {
        id: str(p.id, 96), driver: str(p.driver, 96), name: str(p.name, 40),
        accent: /^#[0-9a-f]{6}$/.test(String(p.accent)) ? p.accent : "",
        enabled: typeof p.enabled === "boolean" ? p.enabled : null,
        status: status, reason: str(p.reason, 160), auth: str(p.auth, 20), plan: str(p.plan, 60), models: models
    };
}

/**
 * bin/kuwai-providers' line, checked: anything not in its shape is "unavailable", never a guess.
 * @param {string} text @returns {Reading}
 */
export function parse(text) {
    let d;
    try { d = JSON.parse(String(text || "")); } catch (e) { return { state: "unavailable", list: [] }; }
    if (!d || typeof d !== "object" || STATES.indexOf(d.state) < 0 || !Array.isArray(d.providers)) return { state: "unavailable", list: [] };
    const list = /** @type {Provider[]} */ (d.providers.map(clean).filter(/** @param {Provider | null} p */ p => p !== null));
    return { state: d.state, list: list };
}

/** @param {Provider[]} list @returns {Record<string, Provider>} */
export function index(list) {
    /** @type {Record<string, Provider>} */
    const out = {};
    for (const p of list || []) out[p.id] = p;
    return out;
}

/** @param {Provider} p @returns {boolean} */
export function pending(p) {
    return p.status === "warning" && PENDING.test(p.reason || "");
}

/**
 * What needs you: a warning or an error, or an instance T3 turned off itself (one you turned off in
 * its settings is your choice, not a problem). Signing in first, then the rest by name.
 * @param {Provider[]} list @returns {Provider[]}
 */
export function trouble(list) {
    return (list || []).filter(p => ((p.status === "warning" || p.status === "error") && !pending(p))
            || (p.status === "disabled" && p.enabled !== false))
        .sort((a, b) => Number(b.auth === "unauthenticated") - Number(a.auth === "unauthenticated")
            || Number(a.status === "disabled") - Number(b.status === "disabled")
            || label(a, "").localeCompare(label(b, "")));
}

/** @param {Provider[]} list @returns {Provider[]} */
export function off(list) {
    return (list || []).filter(p => p.status === "disabled" && p.enabled === false);
}

/** @param {Provider[]} list @returns {Provider[]} */
export function unchecked(list) {
    return (list || []).filter(pending);
}

/**
 * The instance's name as T3 shows it; a bare number ("2", "2nd") gets its agent's name in front.
 * @param {Provider | null | undefined} p @param {string} brand @returns {string}
 */
export function label(p, brand) {
    const n = p && p.name ? p.name : "";
    if (!n) return brand || "";
    return /^\d+(?:st|nd|rd|th)?$/i.test(n) && brand ? brand + " " + n : n;
}

/** @param {Provider} p @returns {string} */
export function why(p) {
    if (p.reason) return p.reason;
    if (p.auth === "unauthenticated") return "Signed out";
    return p.status === "disabled" ? "Turned off" : "Needs attention";
}

/**
 * The Agents footer's one line: the first that needs you, and how many more.
 * @param {Provider[]} list from trouble() @param {(p: Provider) => string} brand @returns {string}
 */
export function line(list, brand) {
    if (!list || !list.length) return "";
    const first = list[0];
    const more = list.length - 1;
    return label(first, brand(first)) + ": " + why(first).replace(/\.$/, "") + (more > 0 ? " · " + more + " more in Usage" : "");
}

/**
 * A model's name as the instance lists it ("claude-opus-5-5" → "Opus 5.5" on a Claude instance: the
 * mark already says Claude). "" when the instance doesn't list it.
 * @param {Provider | null | undefined} p @param {string} slug @returns {string}
 */
export function modelName(p, slug) {
    if (!p || !p.models || !slug) return "";
    const m = p.models.find(x => x[0] === slug);
    if (!m) return "";
    const lead = /^[A-Za-z]+/.exec(label(p, "")) || /^[A-Za-z]+/.exec(p.driver || "");
    const first = /^([A-Za-z]+)\s+(.+)$/.exec(m[1]);
    return lead && first && first[1].toLowerCase() === lead[0].toLowerCase() ? first[2] : m[1];
}

/**
 * Whose model it is, as a brand mark name (shell/assets/brands): "claude-opus-5-5" → claude, "gpt-6.1-sol" → openai,
 * "gemini-4-neon" → googlegemini, "grok-4.7" → grok. "" for a model of the harness's own (composer, swe) or unknown.
 * @param {string} model @returns {string}
 */
export function vendorOf(model) {
    const m = String(model || "").toLowerCase().replace(/^.*\//, "").replace(/^~?(anthropic|openai|google|xai)[-/]/, "");
    if (/^(fusion-)?claude|^(opus|sonnet|haiku|fable)\b/.test(m)) return "claude";
    if (/^(fusion-)?(gpt|o\d|codex)/.test(m)) return "openai";
    if (/^gemini/.test(m)) return "googlegemini";
    if (/^grok/.test(m)) return "grok";
    return "";
}

/**
 * Two letters for a tool with no mark: "Muse Code" → "MC", "Pi" → "Pi", "fx" → "fx", "GLM Agent" → "GA".
 * @param {string} name @returns {string}
 */
export function monogram(name) {
    const words = String(name || "").replace(/[^A-Za-z0-9 ]+/g, " ").trim().split(/\s+/).filter(w => w);
    if (!words.length) return "?";
    if (words.length === 1) return words[0].length <= 2 ? words[0] : words[0].charAt(0).toUpperCase() + words[0].charAt(1).toLowerCase();
    return (words[0].charAt(0) + words[1].charAt(0)).toUpperCase();
}

/**
 * Where a thread stopped by a limit could go on: another instance T3 says is ready whose account (Limits, by the instance's
 * name) has every window under its cap. The same tool first, then the one with most room left. null when none is known
 * to have room: an instance Limits doesn't report isn't offered.
 * @param {Provider[]} list @param {{ name?: string | null, windows?: { used?: number }[] }[]} accounts @param {string} id
 * @returns {Provider | null}
 */
export function roomFor(list, accounts, id) {
    const me = (list || []).find(p => p.id === id);
    /** @param {string} name */
    const used = name => {
        const a = (accounts || []).find(x => x && x.name === name);
        if (!a || !(a.windows || []).length) return -1;
        return Math.max.apply(null, (a.windows || []).map(w => w.used || 0));
    };
    const ready = (list || []).filter(p => p.id !== id && p.status === "ready" && p.enabled !== false && p.name)
        .map(p => ({ p: p, used: used(p.name || "") }))
        .filter(c => c.used >= 0 && c.used < 100)
        .sort((a, b) => Number(!!me && b.p.driver === me.driver) - Number(!!me && a.p.driver === me.driver) || a.used - b.used);
    return ready.length ? ready[0].p : null;
}
