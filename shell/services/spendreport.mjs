// @ts-check

/**
 * One bucket from bin/kuwai-spend-report.
 * @typedef {{ day: string, hour?: string, provider: string, model: string, input?: number, cached?: number, cacheWrite?: number,
 *   output?: number, tokens: number, cost: number, saved?: number, priced?: boolean }} Bucket
 */
/** @typedef {{ id: string, cost: number, tokens: number, sessions: number, share: number }} ProviderRow */
/** @typedef {{ provider: string, model: string, cost: number, tokens: number, share: number }} ModelRow */
/** @typedef {{ key: string, label: string, total: number, parts: Record<string, number> }} Slot */

/** @type {Record<string, string>} */
const NAMES = { claude: "Claude", codex: "Codex", grok: "Grok", cursor: "Cursor", opencode: "OpenCode",
    antigravity: "Antigravity", pi: "Pi", muse: "Muse", gemini: "Gemini" };

/** @param {string} id @returns {string} */
export function providerName(id) {
    const s = String(id || "");
    return NAMES[s] || (s ? s.charAt(0).toUpperCase() + s.slice(1) : "Other");
}

/** @param {number} n @returns {string} */
export function compact(n) {
    const v = Math.max(0, n || 0);
    if (v >= 1e9) return (v / 1e9).toFixed(v >= 1e10 ? 0 : 1) + "B";
    if (v >= 1e6) return (v / 1e6).toFixed(v >= 1e7 ? 0 : 1) + "M";
    if (v >= 1e3) return (v / 1e3).toFixed(v >= 1e4 ? 0 : 1) + "K";
    return String(Math.round(v));
}

/** @param {number} usd @returns {string} */
export function money(usd) {
    const v = Math.max(0, usd || 0);
    if (v === 0) return "$0";
    if (v < 0.01) return "<$0.01";
    if (v >= 1000) return "$" + String(Math.round(v)).replace(/\B(?=(\d{3})+$)/g, ",");
    return "$" + v.toFixed(v >= 100 ? 0 : 2);
}

/** @param {number} n */
function two(n) { return (n < 10 ? "0" : "") + n; }

/** "2026-11-22", in local time (the helper buckets in the same zone). @param {number} ms */
export function dayKey(ms) {
    const d = new Date(ms);
    return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate());
}

/** "2026-11-22T14", local. @param {number} ms */
export function hourKey(ms) { return dayKey(ms) + "T" + two(new Date(ms).getHours()); }

/**
 * The slots the chart draws: each hour of the last day, else each day of the
 * period, oldest first, so an empty one is still a gap in the row.
 * @param {string} period @param {number} now @returns {Slot[]}
 */
export function slots(period, now) {
    /** @type {Slot[]} */
    const out = [];
    if (period === "24h") {
        for (let i = 23; i >= 0; i--) {
            const key = hourKey(now - i * 3600000);
            out.push({ key, label: key.slice(11, 13), total: 0, parts: {} });
        }
        return out;
    }
    const n = period === "90d" ? 90 : period === "30d" ? 30 : 7;
    for (let i = n - 1; i >= 0; i--) {
        const key = dayKey(now - i * 86400000);
        out.push({ key, label: key.slice(8, 10), total: 0, parts: {} });
    }
    return out;
}

/** @param {Bucket} b @param {boolean} hourly @returns {string} */
function slotKey(b, hourly) {
    const t = b.hour ? Date.parse(b.hour) : NaN;
    return !isFinite(t) ? b.day : hourly ? hourKey(t) : dayKey(t);
}

/**
 * Everything the Spend view shows, for one metric ("cost" or "tokens").
 * Providers and models by that metric, largest first; shares of the total.
 * @param {Bucket[]} buckets @param {Record<string, number>} sessions @param {string} period @param {string} metric @param {number} now
 */
export function report(buckets, sessions, period, metric, now) {
    const list = buckets || [];
    /** @param {Bucket} b */
    const val = b => metric === "tokens" ? (b.tokens || 0) : (b.cost || 0);
    const totals = { cost: 0, tokens: 0, input: 0, cached: 0, cacheWrite: 0, output: 0, saved: 0, unpriced: 0 };
    /** @type {Record<string, ProviderRow>} */
    const prov = {};
    /** @type {Record<string, ModelRow>} */
    const mods = {};
    const chart = slots(period, now);
    /** @type {Record<string, Slot>} */
    const at = {};
    for (const s of chart) at[s.key] = s;
    for (const b of list) {
        totals.cost += b.cost || 0;
        totals.tokens += b.tokens || 0;
        totals.input += b.input || 0;
        totals.cached += b.cached || 0;
        totals.cacheWrite += b.cacheWrite || 0;
        totals.output += b.output || 0;
        totals.saved += b.saved || 0;
        if (b.priced === false) totals.unpriced += b.tokens || 0;
        const p = prov[b.provider] || (prov[b.provider] = { id: b.provider, cost: 0, tokens: 0, sessions: (sessions || {})[b.provider] || 0, share: 0 });
        p.cost += b.cost || 0;
        p.tokens += b.tokens || 0;
        const mk = b.provider + "\u0000" + (b.model || "");
        const m = mods[mk] || (mods[mk] = { provider: b.provider, model: b.model || "", cost: 0, tokens: 0, share: 0 });
        m.cost += b.cost || 0;
        m.tokens += b.tokens || 0;
        const s = at[slotKey(b, period === "24h")];
        if (s) {
            s.total += val(b);
            s.parts[b.provider] = (s.parts[b.provider] || 0) + val(b);
        }
    }
    const whole = metric === "tokens" ? totals.tokens : totals.cost;
    /** @param {{ cost: number, tokens: number }} x */
    const of = x => metric === "tokens" ? x.tokens : x.cost;
    const providers = Object.values(prov).map(p => Object.assign(p, { share: whole > 0 ? of(p) / whole : 0 }))
        .filter(p => of(p) > 0).sort((a, b) => of(b) - of(a));
    const models = Object.values(mods).map(m => Object.assign(m, { share: whole > 0 ? of(m) / whole : 0 }))
        .filter(m => of(m) > 0).sort((a, b) => of(b) - of(a));
    const peak = chart.reduce((a, s) => Math.max(a, s.total), 0);
    const sessionsTotal = Object.values(sessions || {}).reduce((a, n) => a + (n || 0), 0);
    return { totals, providers, models, chart, peak, sessions: sessionsTotal, empty: list.length === 0 || whole <= 0 };
}

/** "claude-opus-5-5" → "Opus 5.5", "gpt-6.1-sol" → "GPT-6.1 Sol", "grok-4.7" → "Grok 4.7". @param {string} m @returns {string} */
export function modelName(m) {
    const s = String(m || "").trim();
    if (!s) return "";
    let c = /^claude-([a-z]+)-(\d+)-(\d+)/i.exec(s);
    if (c) return c[1].charAt(0).toUpperCase() + c[1].slice(1) + " " + c[2] + "." + c[3];
    c = /^gpt-([\d.]+)(?:-(.+))?$/i.exec(s);
    if (c) return "GPT-" + c[1] + (c[2] ? " " + c[2].charAt(0).toUpperCase() + c[2].slice(1) : "");
    return s.split("-").map(p => p.charAt(0).toUpperCase() + p.slice(1)).join(" ");
}
