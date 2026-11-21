const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0);

export function dayOf(ms) {
  const d = new Date(ms);
  if (Number.isNaN(d.getTime())) return "";
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function claudeLine(o) {
  const m = o && o.message;
  const u = m && m.usage;
  if (!u || !m.id || o.type === "user") return null;
  const cc = u.cache_creation || {};
  const w1h = num(cc.ephemeral_1h_input_tokens);
  const wAll = num(u.cache_creation_input_tokens);
  return {
    provider: "claude", id: m.id, model: String(m.model || ""), day: dayOf(Date.parse(o.timestamp)),
    in: num(u.input_tokens), out: num(u.output_tokens),
    cacheWrite: Math.max(0, wAll - w1h), cacheWrite1h: w1h, cacheRead: num(u.cache_read_input_tokens),
  };
}

export function codexLine(o, ctx) {
  if (!o) return null;
  const p = o.payload || {};
  if (o.type === "turn_context" || o.type === "session_meta") {
    if (p.model) ctx.model = String(p.model);
    return null;
  }
  if (o.type !== "event_msg" || p.type !== "token_count" || !p.info || !p.info.last_token_usage) return null;
  const u = p.info.last_token_usage;
  const cached = num(u.cached_input_tokens);
  return {
    provider: "codex", model: ctx.model || "", day: dayOf(Date.parse(o.timestamp)),
    in: Math.max(0, num(u.input_tokens) - cached), out: num(u.output_tokens),
    cacheWrite: num(u.cache_write_input_tokens), cacheWrite1h: 0, cacheRead: cached,
  };
}

export function opencodeMessage(o) {
  if (!o || o.role !== "assistant" || !o.tokens) return null;
  const t = o.tokens, c = t.cache || {};
  const rec = {
    provider: "opencode", model: String(o.modelID || ""), day: o.time && o.time.created != null ? dayOf(num(o.time.created)) : "",
    in: num(t.input), out: num(t.output) + num(t.reasoning), cacheWrite: num(c.write), cacheWrite1h: 0, cacheRead: num(c.read),
  };
  if (num(o.cost) > 0) rec.cost = num(o.cost);
  return rec;
}

export function priceOf(table, model) {
  const m = String(model || "").toLowerCase();
  for (const row of (table && table.models) || []) {
    if (new RegExp(row.match).test(m)) return row;
  }
  return null;
}

export function costOf(table, rec) {
  if (typeof rec.cost === "number") return rec.cost;
  const p = priceOf(table, rec.model);
  if (!p) return null;
  const d = (table && table.defaults) || {};
  const read = p.cacheRead != null ? p.cacheRead : p.in * (d.cacheRead ?? 0.1);
  const w5 = p.cacheWrite != null ? p.cacheWrite : p.in * (d.cacheWrite5m ?? 1.25);
  const w1h = p.cacheWrite1h != null ? p.cacheWrite1h : p.in * (d.cacheWrite1h ?? 2);
  return (rec.in * p.in + rec.out * p.out + rec.cacheWrite * w5 + rec.cacheWrite1h * w1h + rec.cacheRead * read) / 1e6;
}

export function add(days, rec, cost) {
  if (!rec || !rec.day) return;
  const prov = (days[rec.provider] ||= {});
  const d = (prov[rec.day] ||= { tokens: 0, cost: 0, unpriced: 0, models: {} });
  const tokens = rec.in + rec.out + rec.cacheWrite + rec.cacheWrite1h + rec.cacheRead;
  d.tokens += tokens;
  if (cost == null) d.unpriced += tokens; else d.cost += cost;
  if (rec.model) d.models[rec.model] = (d.models[rec.model] || 0) + tokens;
}

export function prune(days, today, keep) {
  const cut = dayOf(Date.parse(today + "T12:00:00") - keep * 86400000);
  for (const p of Object.keys(days)) for (const d of Object.keys(days[p])) if (d < cut) delete days[p][d];
}

export function summary(days, today, n = 7) {
  const from = dayOf(Date.parse(today + "T12:00:00") - (n - 1) * 86400000);
  const out = {};
  for (const [p, byDay] of Object.entries(days)) {
    const t = byDay[today] || { tokens: 0, cost: 0, unpriced: 0 };
    let wt = 0, wc = 0, wu = 0;
    for (const [d, v] of Object.entries(byDay)) if (d >= from && d <= today) { wt += v.tokens; wc += v.cost; wu += v.unpriced; }
    out[p] = {
      today: { tokens: t.tokens, cost: round(t.cost), priced: t.unpriced < t.tokens || t.tokens === 0 },
      week: { tokens: wt, cost: round(wc), priced: wu < wt || wt === 0 },
    };
  }
  return out;
}
const round = (v) => Math.round(v * 100) / 100;

export function tokensText(n) {
  if (n >= 1e9) return (n / 1e9).toFixed(1) + "B";
  if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e8 ? 0 : 1) + "M";
  if (n >= 1e3) return Math.round(n / 1e3) + "K";
  return String(Math.round(n));
}

export function completeLines(buf) {
  const end = buf.lastIndexOf(10);
  if (end < 0) return { lines: [], used: 0 };
  return { lines: buf.subarray(0, end).toString("utf8").split("\n"), used: end + 1 };
}
