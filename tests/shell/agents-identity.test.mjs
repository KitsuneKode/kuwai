import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { sessions, counts, stackList, headline, headlineOf, targetOf, limitedOf, ranked, identity, paneKey, merge } from "../../shell/services/agents.mjs";

const now = Date.parse("2026-11-26T12:00:00Z");
const s = now / 1000;
const opts = { home: "/home/u" };

const panes = [
  { key: "w100.1", pid: 100, w: "1", agent: "claude", title: "Fix the notch", state: "working", working: true, since: s - 600, where: "~/Projects/rice" },
  { key: "w100.1", pid: 100, w: "1", agent: "claude", title: "Fix the notch", state: "working", working: true, since: s - 600, where: "~/Projects/rice" },
  { key: "w100.2", pid: 100, w: "2", agent: "codex", title: "API tests", state: "waiting", needs: true, since: s - 120, where: "/home/u/Projects/api" },
  { key: "w100.3", pid: 100, w: "3", agent: "claude", title: "Docs", state: "limited", limitReset: s + 2400, since: s - 60, where: "~/docs" }
];
const threads = [
  { thread: "th-1", provider: "codex", title: "Ship it", status: "waiting", ask: "approval", at: "2026-11-26T11:50:00Z" },
  { thread: "th-1", provider: "codex", title: "Ship it", status: "waiting", ask: "approval", at: "2026-11-26T11:50:00Z" },
  { thread: "th-2", provider: "claudeAgent", title: "Refactor", status: "running", at: "2026-11-26T11:40:00Z" },
  { thread: "th-3", provider: "codex", title: "Old one", status: "completed", at: "2026-11-26T10:00:00Z" }
];
const desktop = [
  { id: "claude-s1", agent: "claude", state: "waiting", ask: "approval", pane: "w100.1", question: "Allow Bash: rm -rf build?", since: s - 30 },
  { id: "codex-s2", agent: "codex", state: "working", cwd: "~/Projects/api", since: s - 300 },
  { id: "cursor-s3", agent: "cursor", state: "working", title: "Cursor chat", window_class: "^(cursor|Cursor)$", since: s - 200 },
  { id: "claude-s4", agent: "claude", state: "working", thread: "th-2", since: s - 100 },
  { id: "cursor-s5", agent: "cursor", state: "done", title: "Finished chat", since: s - 50 }
];

const list = sessions(panes, threads, desktop, opts);
const byKey = Object.fromEntries(list.map(x => [x.key, x]));

describe("one identity per real agent session", () => {
  test("every surface's name for a session meets in one key", () => {
    expect(identity("kitty", panes[0])).toBe("pane:w100.1");
    expect(identity("desktop", desktop[0])).toBe("pane:w100.1");
    expect(identity("t3", threads[2])).toBe("t3:th-2");
    expect(identity("desktop", desktop[3])).toBe("t3:th-2");
    expect(identity("desktop", desktop[2])).toBe("hook:cursor-s3");
    expect(paneKey({ key: "legacy", pid: 7, w: "9" })).toBe("w7.9");
  });
  test("eight sessions from thirteen reports, each once", () => {
    expect(list.map(x => x.key).sort()).toEqual(["hook:cursor-s3", "hook:cursor-s5", "pane:w100.1", "pane:w100.2", "pane:w100.3", "t3:th-1", "t3:th-2", "t3:th-3"]);
    expect(new Set(list.map(x => x.key)).size).toBe(list.length);
  });
  test("a hook inside a kitty pane: the pane's row, the hook's urgency and question", () => {
    const x = byKey["pane:w100.1"];
    expect(x).toMatchObject({ src: "kitty", section: "Terminal", state: "needs", stateKey: "approval", question: "Allow Bash: rm -rf build?" });
    expect(x.sources.sort()).toEqual(["desktop", "kitty"]);
  });
  test("a hook with no pane named, the one pane of its agent in its folder", () => {
    expect(byKey["pane:w100.2"].sources.sort()).toEqual(["desktop", "kitty"]);
    expect(byKey["pane:w100.2"].state).toBe("needs");
  });
  test("two panes of that agent in that folder: the hook stays its own", () => {
    const two = [panes[2], Object.assign({}, panes[2], { key: "w100.9", w: "9" })];
    expect(sessions(two, [], [desktop[1]], opts).map(x => x.key).sort()).toEqual(["hook:codex-s2", "pane:w100.2", "pane:w100.9"]);
  });
  test("a hook in a T3 thread is the thread", () => {
    expect(byKey["t3:th-2"]).toMatchObject({ src: "t3", section: "T3 Code", state: "working", thread: "th-2" });
  });
  test("a desktop agent keeps its window", () => {
    expect(byKey["hook:cursor-s3"]).toMatchObject({ src: "desktop", section: "Desktop", windowClass: "^(cursor|Cursor)$", desktopId: "cursor-s3" });
  });
});

describe("every count agrees", () => {
  const tally = counts(list);
  const head = headlineOf(list, 0, 0, list.filter(x => x.src === "desktop" && x.state === "done").length);
  const needs = stackList(list, "needs"), work = stackList(list, "work");

  test("the tally", () => {
    expect(tally).toMatchObject({ total: 8, needs: 3, working: 2, limited: 1, done: 2, error: 0, idle: 0 });
    expect(tally.bySection).toEqual({ Terminal: 3, "T3 Code": 3, Desktop: 2 });
  });
  test("header, capsule, stack and jump say the same", () => {
    expect(head.count).toBe(tally.needs);
    expect(head.word).toBe("Needs you 3");
    expect(needs.length).toBe(tally.needs);
    expect(head.working).toBe(tally.working);
    expect(work.length).toBe(tally.working);
    expect(head.limited).toBe(tally.limited);
    expect(limitedOf(list).length).toBe(tally.limited);
    expect(ranked(list).filter(x => x.rank === 0).length).toBe(tally.needs);
    expect(targetOf(list).key).toBe("t3:th-1");
  });
  test("sections and sources add up", () => {
    expect(Object.values(tally.bySection).reduce((a, b) => a + b, 0)).toBe(tally.total);
    const src = tally.bySource;
    expect(src.t3 + src.tui + src.desktop).toBe(tally.needs + tally.working);
    expect(head.bySource.t3 + head.bySource.tui + head.bySource.desktop).toBe(tally.needs + tally.working);
  });
  test("the older entry points dedupe the same way", () => {
    const h = headline(panes, threads, 0, 0, now, desktop, 1);
    expect(h.count).toBe(head.count);
    expect(merge(panes, threads, desktop).length).toBe(ranked(sessions(panes, threads, desktop)).length);
  });
  test("the stack: who needs you first, each surface in turn", () => {
    expect(needs.map(x => x.key)).toEqual(["pane:w100.1", "pane:w100.2", "t3:th-1"]);
    expect(needs.every(x => x.needs && x.status === "needs you")).toBe(true);
    expect(work.map(x => x.where)).toEqual(["T3", "Desktop"]);
  });
});

describe("every surface reads the one list", () => {
  const src = f => readFileSync(new URL("../../shell/" + f, import.meta.url), "utf8");
  test("the panel's rows are the sessions, its header the tally", () => {
    const p = src("modules/island/AgentsPanel.qml");
    expect(p).toContain("for (const x of Agents.sessions)");
    expect(p).toContain("readonly property int needN: Agents.tally.needs");
    expect(p).toContain("readonly property int workN: Agents.tally.working");
    expect(p).not.toMatch(/for \(const (r|i|d) of (Kittymux\.running|T3Code\.liveItems|Agents\.desktop)\)/);
  });
  test("the capsule's stack, its light, the notch and the recap", () => {
    expect(src("modules/island/AgentStack.qml")).toContain('Agents.stack("")');
    expect(src("modules/island/IslandSplit.qml")).toContain("readonly property bool agentsNeed: Agents.tally.needs > 0");
    expect(src("modules/island/IslandBar.qml")).toContain("readonly property int waitingCount: Agents.needN");
    expect(src("services/Moments.qml")).toContain("const waiting = Agents.tally.needs;");
    const a = src("services/Agents.qml");
    expect(a).toContain("readonly property int needN: tally.needs");
    expect(a).toContain("A.headlineOf(sessions");
  });
});
