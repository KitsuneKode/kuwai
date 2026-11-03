import { describe, expect, test } from "bun:test";
import { applyEvent, compactedUpTo, sourcesOf, splitFences, chatMarkdown, migrateMessage, newAssistant, pendingRequest, textOf, toApiMessages, toApiMessagesWithIndex, truncateAt } from "./turn.mjs";

const run = (events, msg = newAssistant("hermes3:8b", 1000)) => events.reduce(applyEvent, msg);
const started = (id, itemType, extra = {}) => Object.assign({ type: "item.started", id, itemType, title: "", input: {} }, extra);
const delta = (id, text) => ({ type: "item.delta", id, text });
const done = (id, status = "completed", output = "") => ({ type: "item.completed", id, status, output });

describe("applyEvent", () => {
  test("plain stream builds one text part", () => {
    const m = run([{ type: "turn.started", model: "hermes3:8b" }, started("m1", "assistant_message"),
      delta("m1", "Hel"), delta("m1", "lo"), done("m1"),
      { type: "turn.completed", status: "completed", error: "", stats: { tokensPerSec: 20 } }]);
    expect(m.parts.length).toBe(1);
    expect(m.parts[0]).toMatchObject({ id: "m1", kind: "text", text: "Hello", status: "completed" });
    expect(m.status).toBe("completed");
    expect(m.stats.tokensPerSec).toBe(20);
    expect(textOf(m)).toBe("Hello");
  });

  test("deltas route by id when reasoning and text interleave", () => {
    const m = run([started("r1", "reasoning", { title: "Thinking" }), delta("r1", "a"),
      started("m1", "assistant_message"), delta("m1", "b"), delta("r1", "c")]);
    expect(m.parts.map(p => p.kind)).toEqual(["reasoning", "text"]);
    expect(m.parts[0].text).toBe("ac");
    expect(m.parts[1].text).toBe("b");
  });

  test("tool part goes running → completed with output", () => {
    let m = run([started("t1", "web_search", { title: "Searching", input: { query: "x" } })]);
    expect(m.parts[0]).toMatchObject({ kind: "tool", itemType: "web_search", status: "running", input: { query: "x" } });
    m = applyEvent(m, done("t1", "completed", "result"));
    expect(m.parts[0]).toMatchObject({ status: "completed", output: "result" });
  });

  test("request opened then resolved accept", () => {
    let m = run([started("t1", "command_execution", { title: "ls" }),
      { type: "request.opened", id: "q1", itemId: "t1", kind: "command", summary: "Run a command", detail: "ls" }]);
    expect(m.parts[0].request).toMatchObject({ id: "q1", state: "pending", detail: "ls" });
    expect(pendingRequest(m)).toEqual({ id: "q1", partId: "t1" });
    m = applyEvent(m, { type: "request.resolved", id: "q1", decision: "accept" });
    expect(m.parts[0].request.state).toBe("accept");
    expect(pendingRequest(m)).toBe(null);
  });

  test("turn.completed failed keeps partial text and sets error", () => {
    const m = run([started("m1", "assistant_message"), delta("m1", "par"), done("m1", "failed"),
      { type: "turn.completed", status: "failed", error: "Can't reach Ollama", stats: {} }]);
    expect(textOf(m)).toBe("par");
    expect(m.status).toBe("failed");
    expect(m.error).toBe("Can't reach Ollama");
  });

  test("parts keep start and end times from event ts", () => {
    const m = run([Object.assign(started("r1", "reasoning"), { ts: 1000 }), Object.assign(done("r1"), { ts: 4200 })]);
    expect(m.parts[0].startedAt).toBe(1000);
    expect(m.parts[0].endedAt).toBe(4200);
  });

  test("phase and turn timing", () => {
    const m = run([{ type: "turn.started", ts: 100 }, { type: "turn.phase", phase: "loading" },
      { type: "turn.completed", status: "completed", stats: {}, ts: 3100 }]);
    expect(m.phase).toBe("loading");
    expect(m.startedAt).toBe(100);
    expect(m.endedAt).toBe(3100);
  });

  test("returns new objects (QML needs new references)", () => {
    const a = run([started("m1", "assistant_message")]);
    const b = applyEvent(a, delta("m1", "x"));
    expect(b).not.toBe(a);
    expect(b.parts).not.toBe(a.parts);
    expect(a.parts[0].text).toBe("");
  });

  test("applyEvent ignores unknown event types and unknown ids", () => {
    const a = run([started("m1", "assistant_message")]);
    expect(applyEvent(a, { type: "something.new" })).toBe(a);
    expect(applyEvent(a, delta("zz", "x"))).toBe(a);
  });
});

describe("migrateMessage", () => {
  test("migrateMessage keeps old text, reasoning and tools", () => {
    const old = { role: "assistant", text: "Hi", reasoning: "hmm", time: "10:00", timestamp: 5, model: "hermes3:8b",
      tokensPerSec: 12, tools: [{ name: "launch_app", title: "Launch Application", state: "completed",
        input: { app: "Firefox" }, output: "ok", errorText: "" }] };
    const m = migrateMessage(old);
    expect(m.parts.map(p => p.kind)).toEqual(["reasoning", "tool", "text"]);
    expect(m.parts[0].text).toBe("hmm");
    expect(m.parts[1]).toMatchObject({ title: "Launch Application", status: "completed", output: "ok" });
    expect(textOf(m)).toBe("Hi");
    expect(m.status).toBe("completed");
    expect(m.timestamp).toBe(5);
    expect(m.stats.tokensPerSec).toBe(12);
  });

  test("user messages keep text and image", () => {
    const m = migrateMessage({ role: "user", text: "look", image: "/tmp/a.png", timestamp: 1 });
    expect(m).toMatchObject({ role: "user", text: "look", image: "/tmp/a.png" });
  });

  test("messages that already have parts pass through", () => {
    const m = newAssistant("x", 1);
    expect(migrateMessage(m)).toBe(m);
  });
});

describe("history", () => {
  const user = (text, extra = {}) => Object.assign({ role: "user", text, image: "", timestamp: 1 }, extra);
  const asst = run([started("t1", "web_search"), done("t1", "completed", "big output"),
    started("m1", "assistant_message"), delta("m1", "Answer")]);

  test("toApiMessages drops tool parts", () => {
    const api = toApiMessages([user("q", { image: "/a.png", context: { app: "kitty" } }), asst]);
    expect(api).toEqual([
      { role: "user", content: "q", image: "/a.png", context: { app: "kitty" } },
      { role: "assistant", content: "Answer" },
    ]);
  });

  test("toApiMessages skips failed assistant turns with no text", () => {
    const failed = run([{ type: "turn.completed", status: "failed", error: "x", stats: {} }]);
    expect(toApiMessages([user("q"), failed, user("again")]).map(m => m.role)).toEqual(["user", "user"]);
  });

  test("toApiMessagesWithIndex maps each api message to its chat message", () => {
    const failed = run([{ type: "turn.completed", status: "failed", error: "x", stats: {} }]);
    const r = toApiMessagesWithIndex([user("q0"), failed, user("q1"), asst, user("q2")]);
    expect(r.api.map(m => m.content)).toEqual(["q0", "q1", "Answer", "q2"]);
    expect(r.index).toEqual([0, 2, 3, 4]);
  });

  test("compactedUpTo: kept api messages map back to the first kept chat index", () => {
    // chat from upTo=2: [user q1 (2), asst (3), user q2 (4)] → api index [2,3,4]; kept 1 → covers up to 4
    expect(compactedUpTo(2, [2, 3, 4], 1)).toBe(4);
    expect(compactedUpTo(0, [0, 2, 3, 4], 3)).toBe(2);
    expect(compactedUpTo(5, [], 0)).toBe(5);
  });

  test("truncateAt keeps earlier turns only", () => {
    const msgs = [user("a"), asst, user("b"), asst];
    expect(truncateAt(msgs, 2)).toEqual([msgs[0], msgs[1]]);
  });

  test("truncateAt(0) empties", () => {
    expect(truncateAt([user("a")], 0)).toEqual([]);
  });
});

describe("sourcesOf", () => {
  test("pages read come first, then search results, deduped, at most 4", () => {
    const search = "1. Hyprland 0.57 — https://hypr.land/news/update57/\n   snippet\n2. Releases — https://github.com/hyprwm/Hyprland/releases\n" +
      "3. Wiki — https://wiki.hypr.land/\n4. Reddit — https://www.reddit.com/r/hyprland/x\n5. More — https://example.com/";
    const m = run([started("t1", "web_search", { title: "Searching", input: { query: "q" } }), done("t1", "completed", search),
      started("t2", "dynamic_tool_call", { title: "Reading https://github.com/hyprwm/Hyprland/releases", input: { url: "https://github.com/hyprwm/Hyprland/releases" } }),
      done("t2", "completed", "Releases · hyprwm/Hyprland\n\ntext")]);
    const s = sourcesOf(m);
    expect(s.map(x => x.url)).toEqual(["https://github.com/hyprwm/Hyprland/releases", "https://hypr.land/news/update57/",
      "https://wiki.hypr.land/", "https://www.reddit.com/r/hyprland/x"]);
    expect(s[0]).toMatchObject({ read: true, domain: "github.com", title: "Releases · hyprwm/Hyprland" });
    expect(s[1]).toMatchObject({ read: false, domain: "hypr.land", title: "Hyprland 0.57" });
  });

  test("failed fetches and no web tools give no sources", () => {
    const m = run([started("t1", "dynamic_tool_call", { title: "Reading https://x.org/", input: { url: "https://x.org/" } }), done("t1", "failed", "nope"),
      started("t2", "dynamic_tool_call", { title: "Active window", input: {} }), done("t2", "completed", "App: kitty")]);
    expect(sourcesOf(m)).toEqual([]);
  });
});

describe("steer", () => {
  test("a steer becomes a part where it landed", () => {
    const m = run([started("m1", "assistant_message"), delta("m1", "Half an"), done("m1"),
      { type: "turn.steered", id: "s-1", text: "shorter please" },
      started("m2", "assistant_message"), delta("m2", "Short."), done("m2")]);
    expect(m.parts.map(p => p.kind)).toEqual(["text", "steer", "text"]);
    expect(m.parts[1]).toMatchObject({ id: "s-1", text: "shorter please", status: "completed" });
    expect(textOf(m)).toBe("Half an\n\nShort.");
  });

  test("history splits a steered turn back into assistant / user / assistant", () => {
    const m = run([started("m1", "assistant_message"), delta("m1", "Half an"),
      { type: "turn.steered", id: "s-1", text: "shorter please" },
      started("m2", "assistant_message"), delta("m2", "Short.")]);
    const r = toApiMessagesWithIndex([{ role: "user", text: "explain", image: "", timestamp: 1 }, m], 0);
    expect(r.api).toEqual([
      { role: "user", content: "explain" },
      { role: "assistant", content: "Half an" },
      { role: "user", content: "shorter please" },
      { role: "assistant", content: "Short." },
    ]);
    expect(r.index).toEqual([0, 1, 1, 1]);
  });

  test("unapplied steers are on the finished message for the queue", () => {
    const m = run([{ type: "turn.completed", status: "completed", stats: {}, unapplied: [{ id: "s-2", text: "late" }] }]);
    expect(m.unapplied).toEqual([{ id: "s-2", text: "late" }]);
  });
});

describe("splitFences", () => {
  test("prose and fenced code alternate", () => {
    const t = "Here:\n\n```python\ndef hi():\n    return 1\n```\n\nDone.";
    expect(splitFences(t)).toEqual([
      { kind: "md", text: "Here:" },
      { kind: "code", lang: "python", text: "def hi():\n    return 1", open: false },
      { kind: "md", text: "Done." },
    ]);
  });

  test("a fence still streaming is open", () => {
    expect(splitFences("Try:\n```sh\nls -la")).toEqual([
      { kind: "md", text: "Try:" },
      { kind: "code", lang: "sh", text: "ls -la", open: true },
    ]);
  });

  test("no fences is one prose segment; empty is none", () => {
    expect(splitFences("plain **text**")).toEqual([{ kind: "md", text: "plain **text**" }]);
    expect(splitFences("")).toEqual([]);
  });
});

describe("chatMarkdown", () => {
  test("a chat as Markdown, tools and reasoning left out", () => {
    const a = run([started("t1", "web_search"), done("t1", "completed", "x"), started("m1", "assistant_message"), delta("m1", "Answer.")]);
    expect(chatMarkdown("My chat", [{ role: "user", text: "Question?" }, a]))
      .toBe("# My chat\n\n**You**\n\nQuestion?\n\n**Assistant**\n\nAnswer.\n");
  });
});

