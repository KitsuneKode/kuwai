import { describe, expect, test } from "bun:test";
import { toBuckets, brandOf, sessionsBy, instancesBy, outsideT3, sessionOf, turnsSql } from "../../lib/t3usage.mjs";

const prices = {
  defaults: { cacheRead: 0.1, cacheWrite5m: 1.25 },
  models: [{ match: "^claude-opus-5-5", in: 4, out: 20, cacheRead: 0.2 }, { match: "^gpt-6\\.1-sol", in: 2, out: 10, cacheRead: 0.1, cacheWrite: 2 }]
};
const row = (o) => Object.assign({ inst: "claudeAgent_2", driver: "claudeAgent", model: "claude-opus-5-5", day: "2026-11-26", hour: "2026-11-26T14",
  status: "complete", turns: 1, input: 0, cached: 0, creation: 0, output: 0, reasoning: 0, otherIn: 0, otherOut: 0 }, o);

describe("T3's turns as spend", () => {
  test("input counts its cached and cache-written part: the fresh input is what's left", () => {
    const { buckets } = toBuckets([row({ input: 1_000_000, cached: 900_000, creation: 50_000, output: 10_000 })], prices, false);
    const b = buckets[0];
    expect([b.input, b.cached, b.cacheWrite, b.output, b.tokens]).toEqual([50_000, 900_000, 50_000, 10_000, 1_010_000]);
    expect(b.cost).toBeCloseTo((50_000 * 4 + 10_000 * 20 + 900_000 * 0.2 + 50_000 * 5) / 1e6);
    expect(b.saved).toBeCloseTo(900_000 * 3.8 / 1e6);
    expect(b.priced).toBe(true);
    expect(b.provider).toBe("claude");
    expect(b.instance).toBe("claudeAgent_2");
  });
  test("a model without a price is counted in tokens and said, not priced as 0", () => {
    const { buckets } = toBuckets([row({ driver: "cursor", inst: "cursor_2", model: "composer-2.5", input: 100, output: 10 })], prices, false);
    expect(buckets[0].priced).toBe(false);
    expect(buckets[0].cost).toBe(0);
    expect(buckets[0].tokens).toBe(110);
  });
  test("turns without usage records are counted as turns, never as tokens", () => {
    const r = toBuckets([row({ status: "unavailable", turns: 4 }), row({ status: "partial", turns: 2, input: 10, output: 1 }), row({ turns: 3, input: 5 })], prices, false);
    expect(r.coverage).toEqual({ complete: 3, partial: 2, unavailable: 4 });
    expect(r.buckets.length).toBe(2);
    expect(r.buckets[0].partial).toBe(true);
  });
  test("subagents and compaction count in tokens but aren't priced", () => {
    const { buckets } = toBuckets([row({ input: 0, output: 0, otherIn: 300, otherOut: 20 })], prices, false);
    expect(buckets[0].other).toBe(320);
    expect(buckets[0].cost).toBe(0);
  });
  test("by hour for the last day", () => {
    expect(toBuckets([row({ input: 1 })], prices, true).buckets[0].hour).toBe("2026-11-26T14:00");
    expect(toBuckets([row({ input: 1 })], prices, false).buckets[0].hour).toBe("");
  });
  test("an instance belongs to its tool", () => {
    expect(brandOf("claudeAgent", "claudeAgent_2")).toBe("claude");
    expect(brandOf("codex", "codex_2nd")).toBe("codex");
    expect(brandOf("acpRegistry", "acpRegistry_devin")).toBe("devin");
    expect(brandOf("acpRegistry", "devin_personal")).toBe("devin");
    expect(brandOf("acpRegistry", "acpRegistry_glm_agent")).toBe("glm");
    expect(sessionsBy([{ inst: "claudeAgent", driver: "claudeAgent", n: 2 }, { inst: "claudeAgent_2", driver: "claudeAgent", n: 3 }])).toEqual({ claude: 5 });
    expect(instancesBy([{ inst: "claudeAgent", driver: "claudeAgent" }, { inst: "claudeAgent_2", driver: "claudeAgent" }])).toEqual({ claude: ["claudeAgent", "claudeAgent_2"] });
  });
  test("the query keeps only a time in the time", () => {
    expect(turnsSql("2026-11-20T00:00:00.000Z'; drop table x; --")).not.toContain("drop");
  });
});

describe("this machine's logs, minus what T3 ran", () => {
  const state = { files: {
    "/a.jsonl": { provider: "claude", sid: "t3-run", days: { "2026-11-26": { tokens: 100, cost: 1, unpriced: 0, models: { "claude-opus-5-5": 100 } } } },
    "/b.jsonl": { provider: "claude", sid: "in-kitty", days: { "2026-11-26": { tokens: 40, cost: 0.4, unpriced: 0, models: { "claude-opus-5-5": 40 } },
                                                              "2026-10-01": { tokens: 999, cost: 9, unpriced: 0, models: {} } } },
    "/old-format": { ino: 1, offset: 5 }
  } };
  test("a session T3 ran is counted once, from T3", () => {
    const r = outsideT3(state, new Set(["t3-run"]), "2026-11-20", prices);
    expect(r.buckets.map(b => b.tokens)).toEqual([40]);
    expect(r.buckets[0].local).toBe(true);
    expect(r.sessions).toEqual({ claude: 1 });
  });
  test("nothing cached: nothing added", () => {
    expect(outsideT3(null, new Set(), "2026-11-20", prices)).toEqual({ buckets: [], sessions: {} });
  });
  test("a log file's session", () => {
    expect(sessionOf("claude", "/-home-me-proj/0a1b2c3d-0000-4000-8000-000000000001.jsonl")).toBe("0a1b2c3d-0000-4000-8000-000000000001");
    expect(sessionOf("claude", "/-home-me-proj/0a1b2c3d-0000-4000-8000-000000000001/subagents/agent-1.jsonl")).toBe("0a1b2c3d-0000-4000-8000-000000000001");
    expect(sessionOf("codex", "/2026/11/26/rollout-2026-11-26T17-14-06-01a217ab-86d6-7173-9b0d-088a0eb15918.jsonl")).toBe("01a217ab-86d6-7173-9b0d-088a0eb15918");
    expect(sessionOf("codex", "/x.jsonl")).toBe("");
  });
});
