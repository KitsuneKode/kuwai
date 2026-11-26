import { describe, expect, test } from "bun:test";
import { report, slots, money, compact, providerName, dayKey, hourKey, modelName, valueText, coverageText } from "../../shell/services/spendreport.mjs";

const now = new Date(2026, 10, 22, 14, 30).getTime();
const today = dayKey(now), yesterday = dayKey(now - 86400000);
const b = (o) => Object.assign({ day: today, hour: "", provider: "claude", model: "opus", input: 0, cached: 0, cacheWrite: 0, output: 0, tokens: 100, cost: 1, priced: true }, o);

describe("the chart's slots", () => {
  test("a week is seven days, oldest first, today last", () => {
    const s = slots("7d", now);
    expect(s.length).toBe(7);
    expect(s[6].key).toBe(today);
    expect(s[5].key).toBe(yesterday);
  });
  test("a day is 24 hours ending this hour", () => {
    const s = slots("24h", now);
    expect(s.length).toBe(24);
    expect(s[23].key).toBe(hourKey(now));
    expect(s[23].label).toBe("14");
  });
  test("30 and 90 days", () => {
    expect(slots("30d", now).length).toBe(30);
    expect(slots("90d", now).length).toBe(90);
  });
});

describe("what the Spend view shows", () => {
  const buckets = [
    b({ cost: 3, tokens: 1000 }),
    b({ day: yesterday, cost: 1, tokens: 3000, model: "sonnet" }),
    b({ provider: "codex", model: "gpt", cost: 2, tokens: 6000 }),
  ];
  test("cost: providers by money, shares of the total", () => {
    const r = report(buckets, { claude: 4, codex: 2 }, "7d", "cost", now);
    expect(r.totals.cost).toBe(6);
    expect(r.providers.map(p => p.id)).toEqual(["claude", "codex"]);
    expect(r.providers[0]).toMatchObject({ cost: 4, sessions: 4 });
    expect(r.providers[0].share).toBeCloseTo(4 / 6);
    expect(r.sessions).toBe(6);
  });
  test("tokens: the same buckets ranked by tokens", () => {
    const r = report(buckets, {}, "7d", "tokens", now);
    expect(r.providers.map(p => p.id)).toEqual(["codex", "claude"]);
    expect(r.models[0]).toMatchObject({ provider: "codex", model: "gpt", tokens: 6000 });
  });
  test("each day's slot holds its providers' parts", () => {
    const r = report(buckets, {}, "7d", "cost", now);
    const t = r.chart[6];
    expect(t.total).toBe(5);
    expect(t.parts).toEqual({ claude: 3, codex: 2 });
    expect(r.peak).toBe(5);
  });
  test("hour buckets land in their hour", () => {
    const hour = new Date(now - 2 * 3600000);
    hour.setMinutes(0, 0, 0);
    const r = report([b({ hour: hour.toISOString(), cost: 2 })], {}, "24h", "cost", now);
    expect(r.chart[21].total).toBe(2);
  });
  test("nothing in the period: empty", () => {
    expect(report([], {}, "7d", "cost", now).empty).toBe(true);
    expect(report([b({ cost: 0, tokens: 0 })], {}, "7d", "cost", now).empty).toBe(true);
  });
  test("tokens without a price are shown, never as nothing or $0", () => {
    const r = report([b({ provider: "cursor", model: "composer-2.5", priced: false, cost: 0, tokens: 5e6 })], {}, "7d", "cost", now);
    expect(r.empty).toBe(false);
    expect(r.providers.map(p => p.id)).toEqual(["cursor"]);
    expect(valueText(r.providers[0], false)).toBe("no price · 5.0M");
    expect(r.models[0].priced).toBe(false);
  });
  test("a partly priced provider says so", () => {
    const r = report([b({ provider: "claude", cost: 3, tokens: 10 }), b({ provider: "claude", model: "x", priced: false, cost: 0, tokens: 5 })], {}, "7d", "cost", now);
    expect(valueText(r.providers[0], false)).toBe("$3.00+");
  });
  test("the cache hit rate is cached input over all input", () => {
    const r = report([b({ input: 10, cached: 80, cacheWrite: 10, output: 5, tokens: 105 })], {}, "7d", "tokens", now);
    expect(r.hitRate).toBeCloseTo(0.8);
  });
  test("coverage in words: missing records aren't counted as zero", () => {
    expect(coverageText({ complete: 9, partial: 0, unavailable: 0 })).toBe("");
    expect(coverageText({ complete: 9, partial: 2, unavailable: 1 })).toBe("1 turn without usage records, not counted · 2 turns recorded in part");
    expect(coverageText(null)).toBe("");
  });
  test("unpriced tokens are counted apart", () => {
    expect(report([b({ priced: false, cost: 0, tokens: 50 })], {}, "7d", "tokens", now).totals.unpriced).toBe(50);
  });
});

describe("numbers as words", () => {
  test("money", () => {
    expect(money(0)).toBe("$0");
    expect(money(0.004)).toBe("<$0.01");
    expect(money(4.2)).toBe("$4.20");
    expect(money(204.46)).toBe("$204");
    expect(money(1195.94)).toBe("$1,196");
  });
  test("compact", () => {
    expect(compact(777111593)).toBe("777M");
    expect(compact(5657683766)).toBe("5.7B");
    expect(compact(1500)).toBe("1.5K");
    expect(compact(12)).toBe("12");
  });
  test("provider names", () => {
    expect(providerName("claude")).toBe("Claude");
    expect(providerName("opencode")).toBe("OpenCode");
    expect(providerName("newone")).toBe("Newone");
  });
});

describe("model names", () => {
  test("as people say them", () => {
    expect(modelName("claude-opus-5-5")).toBe("Opus 5.5");
    expect(modelName("gpt-6.1-sol")).toBe("GPT-6.1 Sol");
    expect(modelName("grok-4.7")).toBe("Grok 4.7");
    expect(modelName("")).toBe("");
  });
});
