import { priceOf } from "./spend.mjs";

/**
 * T3 Code's own turn records (statev2.sqlite, orchestration_v2_projection_provider_turns, as T3 Code
 * v0.1.12-nightly.20261125 writes them), read for kuwai's Spend and Tokens view. Only token counts,
 * models, times and instance ids are read; never a message.
 * @typedef {{ inst: string, driver: string, model: string, day: string, hour: string, status: string, turns: number,
 *   input: number, cached: number, creation: number, output: number, reasoning: number, otherIn: number, otherOut: number }} TurnRow
 */

/** @param {string} since ISO time */
export function turnsSql(since) {
  const s = String(since).replace(/[^0-9TZ:.-]/g, "");
  const u = "json_extract(t.payload_json, '$.turnTokenUsage";
  return `with r as (select json_extract(payload_json, '$.activeAttemptId') a, json_extract(payload_json, '$.modelSelection.model') m
                     from orchestration_v2_projection_runs where requested_at >= '${s}')
select coalesce(pt.provider_instance_id, pt.provider, '') inst, coalesce(pt.driver, '') driver,
  coalesce(nullif(json_extract(t.payload_json, '$.model'), ''), ${u}.models[0]'), r.m, '') model,
  date(t.started_at, 'localtime') day, strftime('%Y-%m-%dT%H', t.started_at, 'localtime') hour,
  coalesce(${u}.usageStatus'), 'unavailable') status, count(*) turns,
  sum(coalesce(${u}.inputTokens'), 0)) input, sum(coalesce(${u}.cachedInputTokens'), 0)) cached,
  sum(coalesce(${u}.cacheCreationTokens'), 0)) creation, sum(coalesce(${u}.outputTokens'), 0)) output,
  sum(coalesce(${u}.reasoningTokens'), 0)) reasoning,
  sum(coalesce(${u}.otherUsage.inputTokens'), 0)) otherIn, sum(coalesce(${u}.otherUsage.outputTokens'), 0)) otherOut
from orchestration_v2_projection_provider_turns t
join orchestration_v2_projection_provider_threads pt on pt.provider_thread_id = t.provider_thread_id
left join r on r.a = t.run_attempt_id
where t.started_at >= '${s}'
group by 1, 2, 3, 4, 5, 6;`;
}

/** @param {string} since */
export function sessionsSql(since) {
  const s = String(since).replace(/[^0-9TZ:.-]/g, "");
  return `select coalesce(pt.provider_instance_id, pt.provider, '') inst, coalesce(pt.driver, '') driver, count(distinct t.thread_id) n
from orchestration_v2_projection_provider_turns t
join orchestration_v2_projection_provider_threads pt on pt.provider_thread_id = t.provider_thread_id
where t.started_at >= '${s}' group by 1, 2;`;
}

/** @type {string} The CLI sessions T3 ran itself (its Claude and Codex threads' own ids), so this machine's logs of them aren't counted twice. */
export const NATIVE_SQL = `select distinct json_extract(payload_json, '$.nativeThreadRef.nativeId') id from orchestration_v2_projection_provider_threads
where driver in ('claudeAgent', 'codex', 'opencode') and json_extract(payload_json, '$.nativeThreadRef.nativeId') is not null;`;

const BRAND = /** @type {Record<string, string>} */ ({ claudeAgent: "claude", codex: "codex", cursor: "cursor", antigravity: "antigravity",
  opencode: "opencode", grok: "grok", gemini: "gemini", kiro: "kiro", pi: "pi", muse: "muse", fx: "fx" });

/**
 * The tool a T3 instance runs, as the Spend view groups it: "claudeAgent_2" → claude, an ACP instance by its agent.
 * @param {string} driver @param {string} inst @returns {string}
 */
export function brandOf(driver, inst) {
  if (BRAND[driver]) return BRAND[driver];
  const base = String(inst || "").replace(/^acpRegistry_/, "").replace(/_(\d+|\d+nd|personal|work|main|local|agent)$/, "").toLowerCase();
  if (/devin/.test(base) || /devin/.test(String(inst))) return "devin";
  return BRAND[base] || base || String(driver || "other");
}

/** @param {unknown} v */
const n = v => (Number.isFinite(Number(v)) && Number(v) > 0 ? Number(v) : 0);

/**
 * Turn rows → the Spend view's buckets. Input counts the cached and cache-written tokens too (Claude's and Codex's way,
 * as T3 records them), so the uncached part is what's left. otherUsage (subagents, compaction) is counted in tokens and
 * left unpriced: its split into cached and fresh isn't recorded. A turn without a usage record adds nothing but is counted.
 * @param {TurnRow[]} rows @param {any} prices @param {boolean} hourly
 */
export function toBuckets(rows, prices, hourly) {
  const buckets = [];
  const coverage = { complete: 0, partial: 0, unavailable: 0 };
  for (const r of rows || []) {
    const status = r.status === "complete" || r.status === "partial" ? r.status : "unavailable";
    coverage[status] += n(r.turns);
    const cached = n(r.cached), creation = n(r.creation);
    const fresh = Math.max(0, n(r.input) - cached - creation);
    const output = n(r.output), other = n(r.otherIn) + n(r.otherOut);
    const tokens = fresh + cached + creation + output + other;
    if (tokens <= 0) continue;
    const { cost, saved, priced } = turnCost(r, prices);
    const p = priced;
    buckets.push({
      day: String(r.day || ""), hour: hourly && r.hour ? String(r.hour) + ":00" : "", provider: brandOf(r.driver, r.inst), instance: String(r.inst || ""),
      model: String(r.model || ""), input: fresh, cached, cacheWrite: creation, output, other, tokens, cost, saved,
      priced: !!p, partial: status === "partial"
    });
  }
  return { buckets, coverage };
}

/**
 * What a group of turns would cost at list prices: fresh input, output, cache reads and cache writes, each at its rate.
 * @param {{ model?: string, input?: number, cached?: number, creation?: number, output?: number }} r @param {any} prices
 * @returns {{ cost: number, saved: number, priced: boolean, tokens: number }}
 */
export function turnCost(r, prices) {
  const cached = n(r.cached), creation = n(r.creation);
  const fresh = Math.max(0, n(r.input) - cached - creation), output = n(r.output);
  const tokens = fresh + cached + creation + output;
  const p = priceOf(prices, r.model);
  if (!p) return { cost: 0, saved: 0, priced: false, tokens };
  const d = (prices && prices.defaults) || {};
  const read = p.cacheRead != null ? p.cacheRead : p.in * (d.cacheRead ?? 0.1);
  const write = p.cacheWrite != null ? p.cacheWrite : p.in * (d.cacheWrite5m ?? 1.25);
  return { cost: (fresh * p.in + output * p.out + cached * read + creation * write) / 1e6, saved: cached * Math.max(0, p.in - read) / 1e6, priced: true, tokens };
}

/** @param {{ inst: string, driver: string, n: number }[]} rows @returns {Record<string, number>} */
export function sessionsBy(rows) {
  /** @type {Record<string, number>} */
  const out = {};
  for (const r of rows || []) {
    const b = brandOf(r.driver, r.inst);
    out[b] = (out[b] || 0) + n(r.n);
  }
  return out;
}

/** @param {{ inst: string, driver: string }[]} rows @returns {Record<string, string[]>} */
export function instancesBy(rows) {
  /** @type {Record<string, string[]>} */
  const out = {};
  for (const r of rows || []) {
    const b = brandOf(r.driver, r.inst);
    const list = out[b] || (out[b] = []);
    if (r.inst && list.indexOf(r.inst) < 0) list.push(r.inst);
  }
  return out;
}

/**
 * This machine's own logs (bin/kuwai-spend keeps a day table per log file), minus the sessions T3 ran: those are in
 * T3's records already. What's left is agents run outside T3 (kittymux panes, a terminal).
 * @param {any} state kuwai-spend's cache @param {Set<string>} native @param {string} firstDay @param {any} prices
 */
export function outsideT3(state, native, firstDay, prices) {
  const buckets = [];
  /** @type {Record<string, Set<string>>} */
  const sessions = {};
  for (const f of Object.values((state && state.files) || {})) {
    if (!f || !f.days || !f.provider) continue;
    if (f.sid && native.has(f.sid)) continue;
    for (const [day, d] of Object.entries(f.days)) {
      if (day < firstDay || !d || !(d.tokens > 0)) continue;
      const models = Object.entries(d.models || {});
      const total = models.reduce((a, [, v]) => a + v, 0) || d.tokens;
      for (const [model, v] of models.length ? models : [["", d.tokens]]) {
        const share = v / total;
        const priced = !!priceOf(prices, model);
        buckets.push({ day, hour: "", provider: f.provider, instance: "", model, input: 0, cached: 0, cacheWrite: 0, output: 0, other: 0,
          tokens: v, cost: (d.cost || 0) * share, saved: 0, priced, partial: false, local: true });
      }
      if (f.sid) (sessions[f.provider] || (sessions[f.provider] = new Set())).add(f.sid);
    }
  }
  /** @type {Record<string, number>} */
  const counts = {};
  for (const [p, s] of Object.entries(sessions)) counts[p] = s.size;
  return { buckets, sessions: counts };
}

/**
 * A log file's session: Claude Code names it (projects/<project>/<id>.jsonl, its subagents under <id>/), Codex
 * puts it last in the rollout's name.
 * @param {string} provider @param {string} rel the path under the logs' root
 */
export function sessionOf(provider, rel) {
  const parts = String(rel || "").split("/").filter(Boolean);
  if (provider === "claude") return parts.length >= 2 ? parts[1].replace(/\.jsonl$/, "") : "";
  if (provider === "codex") {
    const m = /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$/i.exec(parts[parts.length - 1] || "");
    return m ? m[1].toLowerCase() : "";
  }
  return "";
}

/**
 * Each listed thread's turns by model, and today's (local) turns by model, for the Agents panel's cost per row and its
 * daily budget.
 * @param {string[]} threads @param {string} todaySince ISO time of local midnight
 */
export function costSql(threads, todaySince) {
  const ids = (threads || []).map(t => String(t).replace(/[^A-Za-z0-9:_.-]/g, "")).filter(t => t).slice(0, 64).map(t => `'${t}'`).join(",");
  const s = String(todaySince).replace(/[^0-9TZ:.-]/g, "");
  const u = "json_extract(t.payload_json, '$.turnTokenUsage";
  const model = `coalesce(nullif(json_extract(t.payload_json, '$.model'), ''), ${u}.models[0]'), (select json_extract(r.payload_json, '$.modelSelection.model')
      from orchestration_v2_projection_runs r where json_extract(r.payload_json, '$.activeAttemptId') = t.run_attempt_id limit 1), '')`;
  const sums = `sum(coalesce(${u}.inputTokens'), 0)) input, sum(coalesce(${u}.cachedInputTokens'), 0)) cached,
  sum(coalesce(${u}.cacheCreationTokens'), 0)) creation, sum(coalesce(${u}.outputTokens'), 0)) output,
  sum(case when ${u}.usageStatus') = 'complete' then 0 else 1 end) gaps`;
  return `select 'thread' kind, t.thread_id id, ${model} model, ${sums} from orchestration_v2_projection_provider_turns t
where t.thread_id in (${ids || "''"}) group by 2, 3
union all
select 'today' kind, '' id, ${model} model, ${sums} from orchestration_v2_projection_provider_turns t
where t.started_at >= '${s}' group by 3;`;
}

/**
 * @param {{ kind: string, id: string, model: string, input: number, cached: number, creation: number, output: number, gaps: number }[]} rows
 * @param {any} prices
 */
export function costs(rows, prices) {
  /** @type {Record<string, { cost: number, priced: boolean }>} */
  const threads = {};
  const today = { cost: 0, tokens: 0, unpriced: 0, gaps: 0 };
  for (const r of rows || []) {
    const c = turnCost(r, prices);
    if (r.kind === "today") {
      today.cost += c.cost;
      today.tokens += c.tokens;
      if (!c.priced) today.unpriced += c.tokens;
      today.gaps += n(r.gaps);
      continue;
    }
    const t = threads[r.id] || (threads[r.id] = { cost: 0, priced: true });
    t.cost += c.cost;
    if (!c.priced && c.tokens > 0) t.priced = false;
  }
  return { threads, today };
}
