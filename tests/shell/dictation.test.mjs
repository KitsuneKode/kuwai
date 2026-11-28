import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import * as D from "../../shell/services/dictation.mjs";

const vox = { installed: true, answered: true, running: true, state: "idle", engine: "parakeet", model: "parakeet-unified-en-0.6b-fp16", backend: "GPU (Vulkan)", gpu: true, model_state: "loaded", unload_after: 120, config: { warm: 3, tail: 400, queue: true, preedit: true } };
const report = (v, s) => ({ at: 0, voxtype: v || vox, last: null, shuush: s || { installed: false } });
const INSIDES = /\bkuwai-[a-z]{3,}\b|\bexit(?:ed)?(?: with| code| status)? \d+\b|\bundefined\b|\bNaN\b|\[object |voxtype|shuush/;

describe("status", () => {
  test("idle, listening, writing and stopped are plain words", () => {
    expect(D.status(report(), "idle").chip).toBe("Ready");
    expect(D.status(report(), "streaming").chip).toBe("Listening");
    expect(D.status(report(), "recording").tone).toBe("busy");
    expect(D.status(report(), "transcribing").chip).toBe("Writing");
    expect(D.status(report({ ...vox, running: false }), "").chip).toBe("Off");
    expect(D.status(report(), "stopped").tone).toBe("bad");
  });
  test("the live state wins over the one read when the page opened", () => {
    expect(D.liveState(report({ ...vox, state: "idle" }), "recording")).toBe("recording");
    expect(D.liveState(report({ ...vox, state: "transcribing" }), "")).toBe("transcribing");
  });
  test("no engine is one sentence, never a name", () => {
    const s = D.status(report({ installed: false }), "idle");
    expect(s.chip).toBe("Not installed");
    expect(INSIDES.test(s.detail)).toBe(false);
    expect(D.status(null, "").chip).toBe("Not installed");
  });
});

describe("engine and model", () => {
  test("where it runs", () => {
    expect(D.engine(vox)).toBe("Parakeet on the graphics card (Vulkan)");
    expect(D.engine({ ...vox, backend: "CPU", gpu: false, engine: "whisper" })).toBe("Whisper on the processor");
    expect(D.engine({ ...vox, engine: "newthing", backend: "", gpu: null })).toBe("Newthing");
    expect(D.engine({ ...vox, engine: "" })).toBe("");
  });
  test("loaded, set aside, or loaded for each take", () => {
    expect(D.model(vox)).toBe("Ready in memory; set aside after 2 min without a take");
    expect(D.model({ ...vox, unload_after: 0 })).toBe("Ready in memory");
    expect(D.model({ ...vox, model_state: "unloaded" })).toMatch(/next take loads it/);
    expect(D.model({ ...vox, model_state: "on_demand" })).toMatch(/each take/);
    expect(D.model({ ...vox, running: false })).toBe("");
  });
});

describe("the last take", () => {
  const now = 1_800_000_000_000;
  test("delivered says when and how much", () => {
    expect(D.lastTake({ outcome: "ok", at: now - 12 * 60000, chars: 157 }, now).detail).toBe("Delivered 12 min ago, 157 characters");
    expect(D.lastTake({ outcome: "delivered", at: now - 5000, chars: 1 }, now).detail).toBe("Delivered just now, 1 character");
  });
  test("every outcome voxtype writes reads as a sentence", () => {
    for (const o of ["ok", "delivered", "recovered", "clipboard_only", "private_not_inserted", "output_failed", "failed", "error", "no_speech", "no_input", "too_short", "empty", "cancelled"]) {
      const t = D.lastTake({ outcome: o, at: now - 3 * 3600000, chars: 0 }, now);
      expect(t.title).not.toBe("");
      expect(t.detail).toContain("3 h ago");
      expect(INSIDES.test(t.detail)).toBe(false);
      expect(t.detail).not.toContain("_");
    }
  });
  test("a take that hit the limit says so; none yet says so", () => {
    expect(D.lastTake({ outcome: "recovered", at: now - 2 * 86400000, chars: 10, limit: true }, now).detail).toMatch(/2 days ago.*longest take/);
    expect(D.lastTake(null, now).detail).toBe("No take yet since dictation started");
    expect(D.lastTake({ outcome: "made_up" }, now).title).toBe("");
  });
});

describe("cleanup", () => {
  test("the order, and where the words go", () => {
    const c = D.cleanup({ order: ["groq", "groq2", "openrouter"] });
    expect(c.chain).toBe("Groq, then Groq (second key), then OpenRouter");
    expect(c.local).toBe(false);
    expect(c.where).toMatch(/^Online/);
    expect(D.cleanup({ order: ["local"], offline: true })).toMatchObject({ local: true, offline: true, chain: "Ollama on this computer" });
    expect(D.cleanup({ order: ["local", "groq"] }).where).toMatch(/^This computer first/);
    expect(D.cleanup({ order: ["groq", "local"] }).where).toMatch(/^Online first/);
    expect(D.cleanup({ order: [] }).chain).toBe("Words arrive as they were heard");
    expect(D.cleanup(null).local).toBe(true);
  });
});

describe("learning, speed and reliability", () => {
  test("counts by where they came from, the empty ones left out", () => {
    const l = D.learning({ rules: 43, by_source: { seed: 32, auto: 6, "user fix": 4, "accepted hint": 1, "edit-watch": 0 }, pending_fixes: 6, pending_vocab: 0, vocab: 55 });
    expect(l.rules).toBe("43 corrections: 32 built in, 6 learned by itself, 4 your fixes, 1 suggestion you accepted");
    expect(l.pending).toBe("6 suggestions wait for you");
    expect(l.vocab).toBe("55 words it listens out for");
    expect(D.learning({ rules: 0, by_source: {}, pending_fixes: 0, pending_vocab: 1, vocab: 0 })).toMatchObject({ pending: "1 suggestion waits for you", vocab: "No words of your own yet" });
    expect(D.learning(null).rules).toBe("");
  });
  test("speed in ms or seconds; missing stats say when they'll come", () => {
    expect(D.ms(581)).toBe("580 ms");
    expect(D.ms(1178)).toBe("1.2 s");
    expect(D.ms(-1)).toBe("");
    expect(D.speed({ n: 48, p50: 610, p90: 1180 })).toEqual({ value: "610 ms", detail: "Half of takes within 610 ms, nine in ten within 1.2 s, over the last 48 takes" });
    expect(D.speed(null).detail).toBe("Measured after a few dictations");
    expect(D.delivered({ n: 100, rate: 0.97 })).toEqual({ value: "97 %", detail: "97 of the last 100 takes reached their field" });
    expect(D.delivered(null).value).toBe("");
  });
});

describe("choices and keys", () => {
  test("a value set elsewhere is kept as a choice", () => {
    expect(D.options([0, 3, 5], 3, n => n + " s").map(o => o.label)).toEqual(["Off", "3 s", "5 s"]);
    expect(D.options([0, 3, 5], 10, n => n + " s").map(o => o.id)).toEqual(["0", "3", "5", "10"]);
    expect(D.options([0, 200], null, n => n + " ms").length).toBe(2);
  });
  test("the dictation keys are the [Dictation] group's", () => {
    expect(D.keys([{ group: "Dictation", text: "a", keys: "F9" }, { group: "Windows", text: "b", keys: "F1" }, null, { group: "Dictation", text: "a", keys: "SUPER + D" }, { group: "Dictation", text: "c", keys: "" }]))
      .toEqual([{ text: "a", chords: ["F9", "SUPER + D"] }, { text: "c", chords: [] }]);
    expect(D.keys(undefined)).toEqual([]);
  });
});

describe("words on screen", () => {
  const schema = JSON.parse(readFileSync(new URL("../../shell/config/settings-schema.json", import.meta.url), "utf8"));
  const allowed = schema.settings.find(e => e.key === "dictationPill").enum;
  test("every value the schema allows is offered, with a line saying what it does", () => {
    const c = D.pillChoices(allowed);
    expect(c.map(x => x.id).sort()).toEqual([...allowed].sort());
    for (const x of c) expect(x.detail.length).toBeGreaterThan(20);
  });
  test("the island comes first once the schema has it; a value this page doesn't know still shows", () => {
    expect(D.pillChoices(["field", "words", "ticker", "status"]).map(x => x.label)).toEqual(["Ticker", "Field", "Words", "Status"]);
    expect(D.pillChoices(["field", "words", "ticker", "status", "island"]).map(x => x.id)).toEqual(["island", "ticker", "field", "words", "status"]);
    expect(D.pillChoices(["ticker", "corner"]).map(x => x.label)).toEqual(["Ticker", "Corner"]);
    expect(D.pillDetail(D.pillChoices(["island"]), "island")).toMatch(/^In the island/);
    expect(D.pillChoices(undefined)).toEqual([]);
  });
});

describe("the page", () => {
  const page = readFileSync(new URL("../../shell/modules/island/DictationPage.qml", import.meta.url), "utf8");
  const svc = readFileSync(new URL("../../shell/services/Dictation.qml", import.meta.url), "utf8");
  test("reads only while open, and never on a timer of its own", () => {
    expect(page).toMatch(/Component\.onCompleted:[^\n]*Dictation\.open\(\)/);
    expect(page).toMatch(/Component\.onDestruction:\s*Dictation\.close\(\)/);
    expect(svc).not.toMatch(/repeat:\s*true/);
    expect(svc).not.toMatch(/running:\s*true/);
  });
  test("a change reaches the helper as arguments, never inside a script", () => {
    expect(svc).toMatch(/setter\.command = \[bin, "set", name,/);
    expect(svc).not.toMatch(/"sh", "-c"/);
  });
  test("its studio buttons go through Apps.run", () => {
    expect(page).toMatch(/Apps\.run\(/);
    expect(page).not.toMatch(/execDetached/);
  });
});
