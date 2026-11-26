import { describe, expect, test } from "bun:test";
import { parse, index, trouble, off, unchecked, label, why, line, modelName, vendorOf, monogram } from "../../shell/services/providers.mjs";

const claude = { id: "claudeAgent_2", driver: "claudeAgent", name: "Claude-2", accent: "#eb2575", enabled: true, status: "ready",
  reason: "", auth: "authenticated", plan: "Claude Pro Subscription", models: [["claude-opus-5-5", "Claude Opus 5.5"]] };
const codexOut = { id: "codex_9", driver: "codex", name: "codex-2", accent: "", enabled: true, status: "warning", reason: "Sign in with ChatGPT to use Codex.",
  auth: "unauthenticated", plan: "", models: [] };
const acp = { id: "devin_local", driver: "acpRegistry", name: "Local ACP", accent: "", enabled: true, status: "warning",
  reason: "The ACP agent could not create a test session.", auth: "unknown", plan: "", models: [] };
const ocPending = { id: "oc", driver: "opencode", name: "2", accent: "", enabled: true, status: "warning",
  reason: "OpenCode provider status has not been checked in this session yet.", auth: "unknown", plan: "", models: [] };
const piOff = { id: "pi", driver: "pi", name: "Pi", accent: "", enabled: false, status: "disabled", reason: "Pi is disabled in T3 Code settings.",
  auth: "unknown", plan: "", models: [] };
const notInstalled = { id: "kiro", driver: "kiro", name: "Kiro", accent: "", enabled: true, status: "disabled", reason: "",
  auth: "unknown", plan: "", models: [] };
const codexReady = { id: "codex", driver: "codex", name: "Codex", accent: "", enabled: true, status: "ready", reason: "", auth: "authenticated",
  plan: "", models: [["gpt-6.2-sol", "GPT-6.2-Sol"]] };

const doc = (providers, state = "ok") => JSON.stringify({ state, providers });

describe("the reader's line", () => {
  test("read as given", () => {
    expect(parse(doc([claude, piOff]))).toEqual({ state: "ok", list: [claude, piOff] });
  });
  test("anything else is unavailable, never a guess", () => {
    expect(parse("")).toEqual({ state: "unavailable", list: [] });
    expect(parse("{nope")).toEqual({ state: "unavailable", list: [] });
    expect(parse(JSON.stringify({ state: "great", providers: [] }))).toEqual({ state: "unavailable", list: [] });
    expect(parse(JSON.stringify({ state: "ok" }))).toEqual({ state: "unavailable", list: [] });
    const odd = parse(doc([{ id: "x", status: "sleeping", name: "X" }, { status: "ready" }, null, { id: "y", status: "unavailable", name: "Y" }]));
    expect(odd.list).toEqual([{ id: "x", status: "unavailable" }, { id: "y", status: "unavailable" }]);
  });
  test("a colour that isn't #rrggbb is dropped", () => {
    expect(parse(doc([Object.assign({}, claude, { accent: "red" })])).list[0].accent).toBe("");
  });
  test("indexed by instance", () => {
    expect(index([claude, piOff]).pi).toBe(piOff);
  });
});

describe("health", () => {
  const all = [claude, ocPending, piOff, acp, notInstalled, codexOut, codexReady];
  test("what needs you: signing in first, then other warnings, then one T3 turned off itself", () => {
    expect(trouble(all).map(p => p.id)).toEqual(["codex_9", "devin_local", "kiro"]);
  });
  test("one you turned off is yours, not a problem", () => {
    expect(off(all).map(p => p.id)).toEqual(["pi"]);
    expect(trouble([piOff])).toEqual([]);
  });
  test("not checked yet is not wrong", () => {
    expect(unchecked(all).map(p => p.id)).toEqual(["oc"]);
    expect(trouble([ocPending])).toEqual([]);
  });
  test("the Agents footer: the first, and how many more", () => {
    const brand = () => "Codex";
    expect(line([], brand)).toBe("");
    expect(line([codexOut], brand)).toBe("codex-2: Sign in with ChatGPT to use Codex");
    expect(line(trouble(all), brand)).toBe("codex-2: Sign in with ChatGPT to use Codex · 2 more in Usage");
  });
  test("a reason in words even when T3 gave none", () => {
    expect(why(notInstalled)).toBe("Turned off");
    expect(why(Object.assign({}, codexOut, { reason: "" }))).toBe("Signed out");
    expect(why(Object.assign({}, acp, { reason: "" }))).toBe("Needs attention");
  });
});

describe("names", () => {
  test("as T3 names the instance; a bare number gets its agent's name", () => {
    expect(label(claude, "Claude")).toBe("Claude-2");
    expect(label(ocPending, "OpenCode")).toBe("OpenCode 2");
    expect(label(Object.assign({}, codexReady, { name: "2nd" }), "Codex")).toBe("Codex 2nd");
    expect(label(null, "Claude")).toBe("Claude");
    expect(label({ id: "x", status: "unavailable" }, "")).toBe("");
  });
  test("a model by the name the instance lists, without the vendor the mark already shows", () => {
    expect(modelName(claude, "claude-opus-5-5")).toBe("Opus 5.5");
    expect(modelName(codexReady, "gpt-6.2-sol")).toBe("GPT-6.2-Sol");
    expect(modelName(claude, "claude-haiku-9")).toBe("");
    expect(modelName(null, "claude-opus-5-5")).toBe("");
  });
});

describe("marks", () => {
  test("whose model it is, for the badge on a harness that runs others' models", () => {
    expect(vendorOf("claude-opus-5-5")).toBe("claude");
    expect(vendorOf("fusion-claude-opus-5-5-high-sidekick-swe-2-high")).toBe("claude");
    expect(vendorOf("gpt-6.2-astra")).toBe("openai");
    expect(vendorOf("fusion-gpt-6-2-sol-high-sidekick-swe-2-medium")).toBe("openai");
    expect(vendorOf("gemini-3.8-flash-high")).toBe("googlegemini");
    expect(vendorOf("grok-4.7")).toBe("grok");
    expect(vendorOf("openrouter/~anthropic/claude-opus-latest")).toBe("claude");
    expect(vendorOf("composer-2.5")).toBe("");
    expect(vendorOf("swe-2-flash-medium")).toBe("");
    expect(vendorOf("")).toBe("");
  });
  test("two letters where there is no mark", () => {
    expect(monogram("Muse Code")).toBe("MC");
    expect(monogram("Pi")).toBe("Pi");
    expect(monogram("fx")).toBe("fx");
    expect(monogram("GLM Agent")).toBe("GA");
    expect(monogram("opencode")).toBe("Op");
    expect(monogram("")).toBe("?");
  });
});
