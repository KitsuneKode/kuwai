import { describe, expect, test } from "bun:test";
import { headline, limitedItems, target, merge, until, t3Agent, stateGlyph, stackMarks, providerId } from "../../shell/services/agents.mjs";

const now = Date.parse("2026-11-22T12:00:00Z");
const pane = (o) => Object.assign({ key: "p", agent: "claude", state: "working", working: true, since: 0 }, o);
const thread = (o) => Object.assign({ thread: "t", provider: "codex", status: "running", at: "2026-11-22T11:00:00Z" }, o);
const desktop = (o) => Object.assign({ id: "cur-1", agent: "cursor", state: "working", title: "Refactor", window_class: "^(cursor|Cursor)$", since: now / 1000 - 30 }, o);

describe("one capsule says the one thing that matters most", () => {
  test("nothing going on: nothing to say", () => {
    expect(headline([], [], 0, 0, now)).toMatchObject({ word: "", tone: "", working: 0, done: 0, limited: 0 });
  });
  test("only working: no word, counts all three surfaces", () => {
    const h = headline([pane({})], [thread({})], 0, 0, now, [desktop({})], 0);
    expect(h).toMatchObject({ word: "", tone: "working", working: 3, bySource: { t3: 1, tui: 1, desktop: 1 } });
  });
  test("an approval in T3 outranks kitty agents working and carries shield glyph", () => {
    const h = headline([pane({}), pane({ key: "q" })], [thread({ status: "waiting", ask: "approval" })], 0, 0, now);
    expect(h).toMatchObject({ word: "Approval", glyph: stateGlyph("approval"), tone: "attention", count: 1, working: 2 });
  });
  test("two approvals, one from each, say Approval 2", () => {
    const h = headline([pane({ state: "waiting", needs: true, working: false, ask: true })], [thread({ status: "waiting", ask: "approval" })], 0, 0, now);
    expect(h.word).toBe("Approval 2");
    expect(h.glyph).toBe(stateGlyph("approval"));
  });
  test("different asks say Needs you with the count", () => {
    const h = headline([pane({ state: "waiting", needs: true, working: false })], [thread({ status: "waiting", ask: "question" })], 0, 0, now);
    expect(h.word).toBe("Needs you 2");
    expect(h.glyph).toBe(stateGlyph("waiting"));
  });
  test("desktop approval surfaces cleanly with question/approval glyph", () => {
    const h = headline([], [], 0, 0, now, [desktop({ state: "waiting", ask: "approval" })], 0);
    expect(h).toMatchObject({ word: "Approval", glyph: stateGlyph("approval"), tone: "attention", count: 1, bySource: { desktop: 1 } });
  });
  test("a failure outranks working and limits", () => {
    const h = headline([pane({ state: "limited", working: false, limitReset: now / 1000 + 2460 })], [thread({ status: "failed" })], 0, 0, now);
    expect(h).toMatchObject({ word: "Failed", glyph: stateGlyph("failed"), tone: "error", limited: 1 });
  });
  test("limits never hijack active agents on the left and flow to limitedItems", () => {
    const panes = [
      pane({ key: "work", state: "working", working: true }),
      pane({ key: "lim", state: "limited", working: false, limitReset: now / 1000 + 2460 })
    ];
    const h = headline(panes, [thread({ status: "failed", limited: true })], 0, 0, now);
    expect(h).toMatchObject({ word: "", tone: "working", working: 1, limited: 2 });
    const lims = limitedItems(panes, [thread({ status: "failed", limited: true })]);
    expect(lims.length).toBe(2);
    expect(lims[0].reset).toBe((now / 1000 + 2460) * 1000);
  });
  test("only limited agents leave left capsule quiet while reporting limited count", () => {
    const h = headline([], [thread({ status: "failed", limited: true })], 0, 0, now);
    expect(h).toMatchObject({ word: "", tone: "", working: 0, limited: 1 });
  });
  test("finished and unseen counts all surfaces", () => {
    expect(headline([], [], 2, 3, now, [], 1)).toMatchObject({ tone: "done", done: 6, glyph: stateGlyph("done") });
  });
});

describe("go to what needs me", () => {
  test("the one that has waited longest", () => {
    const t = target([pane({ key: "late", state: "waiting", needs: true, working: false, since: now / 1000 - 60 })],
      [thread({ thread: "early", status: "waiting", ask: "approval", at: "2026-11-22T11:00:00Z" })]);
    expect(t).toMatchObject({ src: "t3", thread: "early" });
  });
  test("desktop agent needing approval is jumpable", () => {
    const t = target([], [], [desktop({ id: "dev-1", agent: "devin", state: "waiting", ask: "approval", window_class: "^(devin|Devin)$" })]);
    expect(t).toMatchObject({ src: "desktop", agent: "devin", windowClass: "^(devin|Devin)$", desktopId: "dev-1" });
  });
  test("a kitty pane carries its event and action", () => {
    const t = target([pane({ state: "waiting", needs: true, working: false, event: "e1", action: { w: 3 } })], []);
    expect(t).toMatchObject({ src: "kitty", event: "e1", action: { w: 3 } });
  });
  test("working and limited agents are never the jump target", () => {
    expect(target([pane({}), pane({ key: "l", state: "limited", working: false })], [thread({})])).toBeNull();
  });
  test("a failure is, when nothing asks", () => {
    expect(target([pane({ state: "error", working: false })], [])).toMatchObject({ src: "kitty", word: "Failed" });
  });
  test("idle and done ones are left out of the merged list", () => {
    expect(merge([pane({ state: "idle", working: false })], [thread({ status: "completed" })], [desktop({ state: "done" })])).toEqual([]);
  });
});

describe("small readings", () => {
  test("until", () => {
    expect(until(now + 125 * 60000, now)).toBe("2h 5m");
    expect(until(now + 60 * 60000, now)).toBe("1h");
    expect(until(now - 1, now)).toBe("");
  });
  test("T3 providers as kittymux's marks", () => {
    expect(t3Agent("claudeAgent")).toBe("claude");
    expect(t3Agent("codex_2")).toBe("codex");
    expect(t3Agent("devin")).toBe("devin");
    expect(t3Agent("newthing")).toBe("newthing");
  });
});

describe("the capsule's marks", () => {
  test("each provider once, counted, the one that needs you first", () => {
    const r = stackMarks([
      { agent: "claude" }, { agent: "codex" }, { agent: "claude" },
      { agent: "antigravity", needs: true }, { agent: "claude" }
    ], 3);
    expect(r.marks).toEqual([
      { agent: "antigravity", count: 1, needs: true },
      { agent: "claude", count: 3, needs: false },
      { agent: "codex", count: 1, needs: false }
    ]);
    expect(r.more).toBe(0);
  });

  test("past the cap, a count of the rest", () => {
    const r = stackMarks(["a", "b", "c", "d", "e"].map(agent => ({ agent })), 3);
    expect(r.marks.map(m => m.agent)).toEqual(["a", "b", "c"]);
    expect(r.more).toBe(2);
    expect(stackMarks([], 3)).toEqual({ marks: [], more: 0 });
  });
});

test("T3's provider instances read as their agent", () => {
  expect(t3Agent("claudeAgent_2")).toBe("claude");
  expect(t3Agent("devin_personal")).toBe("devin");
  expect(t3Agent("acpRegistry_devin")).toBe("devin");
  expect(t3Agent("codex_2")).toBe("codex");
});

describe('one provider id whichever source names it', () => {
    test('kittymux and T3 names meet', () => {
        expect(providerId('agy')).toBe('antigravity');
        expect(providerId('antigravity')).toBe('antigravity');
        expect(providerId('cursor-agent')).toBe('cursor');
        expect(providerId('claudeAgent')).toBe('claude');
        expect(providerId('acpRegistry_devin')).toBe('devin');
        expect(providerId('Codex')).toBe('codex');
    });
});
