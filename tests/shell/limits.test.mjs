import { describe, expect, test } from "bun:test";
import { compactDuration, partitionLimits, summarizeLimits } from "../../shell/services/limits.mjs";

const now = Date.parse("2026-11-24T12:00:00Z");
const soonMs = 15 * 60000;

const entry = (o) => Object.assign({
  key: "k",
  id: "claude",
  brand: "claude.svg",
  tint: "#d97757",
  name: "Claude",
  account: "",
  resetsAt: now + 90 * 60000,
  windowLabel: "5-hour",
  source: "quota"
}, o);

describe("partitionLimits splits resetting soon from exhausted", () => {
  test("<=15m goes to resettingSoon, >15m and unknown go to exhaustedLater", () => {
    const res = partitionLimits([
      entry({ key: "a", id: "claude", name: "Claude", resetsAt: now + 4 * 60000 }),
      entry({ key: "b", id: "codex", name: "Codex", resetsAt: now + 15 * 60000 }),
      entry({ key: "c", id: "cursor", name: "Cursor", resetsAt: now + 90 * 60000 }),
      entry({ key: "d", id: "grok", name: "Grok", resetsAt: 0 })
    ], [], now, soonMs);

    expect(res.resettingSoon.map(x => x.id)).toEqual(["claude", "codex"]);
    expect(res.exhaustedLater.map(x => x.id)).toEqual(["cursor", "grok"]);
  });

  test("deduplicates by provider+account keeping soonest reset and drops expired resets", () => {
    const res = partitionLimits([
      entry({ key: "w1", id: "claude", name: "Claude", account: "work", resetsAt: now + 120 * 60000 }),
      entry({ key: "w2", id: "claude", name: "Claude", account: "work", resetsAt: now + 10 * 60000 }),
      entry({ key: "w3", id: "claude", name: "Claude", account: "personal", resetsAt: now + 60 * 60000 }),
      entry({ key: "expired", id: "codex", name: "Codex", resetsAt: now - 1000 })
    ], [], now, soonMs);

    expect(res.resettingSoon.map(x => x.account)).toEqual(["work"]);
    expect(res.exhaustedLater.map(x => x.account)).toEqual(["personal"]);
  });

  test("quota entries win over session-reported limits for the same provider", () => {
    const res = partitionLimits(
      [entry({ id: "claude", name: "Claude", resetsAt: now + 60 * 60000, source: "quota" })],
      [
        entry({ id: "claude", name: "Claude", resetsAt: now + 5 * 60000, source: "kitty" }),
        entry({ id: "codex", name: "Codex", resetsAt: now + 45 * 60000, source: "kitty" })
      ],
      now,
      soonMs
    );

    expect(res.resettingSoon).toEqual([]);
    expect(res.exhaustedLater.map(x => x.id + ":" + x.source)).toEqual(["codex:kitty", "claude:quota"]);
  });
});

describe("carousel formatting and stacked brand ordering", () => {
  test("compactDuration formats largest unit", () => {
    expect(compactDuration(45000)).toBe("1m");
    expect(compactDuration(14 * 60000)).toBe("14m");
    expect(compactDuration(2 * 3600000)).toBe("2h");
    expect(compactDuration(3 * 86400000)).toBe("3d");
    expect(compactDuration(0)).toBe("");
  });

  test("one summary: the soonest reset, the state, each provider once", () => {
    const part = partitionLimits([
      entry({ key: "a1", id: "antigravity", name: "Antigravity", account: "Antigravity-2", resetsAt: now + 15 * 60000 }),
      entry({ key: "a2", id: "antigravity", name: "Antigravity", account: "Antigravity", resetsAt: now + 25 * 60000 }),
    ], [], now, soonMs);
    const s = summarizeLimits(part, now);
    expect(s.label).toBe("15m");
    expect(s.tone).toBe("soon");
    expect(s.providers.map(p => [p.id, p.count])).toEqual([["antigravity", 2]]);
    expect(s.items.length).toBe(2);
  });

  test("out for longer is its own state, an unknown reset says Out", () => {
    const later = summarizeLimits(partitionLimits([entry({ resetsAt: now + 90 * 60000 }), entry({ key: "g", id: "grok", name: "Grok", resetsAt: 0 })], [], now, soonMs), now);
    expect(later.tone).toBe("out");
    expect(later.label).toBe("1h");
    expect(later.providers.map(p => p.id)).toEqual(["claude", "grok"]);
    const unknown = summarizeLimits(partitionLimits([entry({ resetsAt: 0 })], [], now, soonMs), now);
    expect(unknown.label).toBe("Out");
    expect(summarizeLimits({ resettingSoon: [], exhaustedLater: [] }, now).tone).toBe("");
  });
});
