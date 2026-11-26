import { expect, test } from "bun:test";
import { functions } from "../helpers/qml.mjs";

const L = functions("shell/services/Limits.qml", ["poolOf", "stateOf"], {});
const w = (label, level) => ({ window: { label }, level });

test("every pool exhausted, some in two windows, is out", () => {
  const s = L.stateOf([w("Gemini · 5-hour", "exhausted"), w("Gemini · Weekly", "exhausted"), w("Claude · Weekly", "exhausted")]);
  expect(s.out).toBe(true);
  expect(s.partial).toBe(false);
});

test("one pool of two exhausted is partly out", () => {
  const s = L.stateOf([w("Gemini · Weekly", "exhausted"), w("Claude · Weekly", "ok")]);
  expect(s.out).toBe(false);
  expect(s.partial).toBe(true);
  expect(s.pool).toBe("Gemini");
});

test("an exhausted limit that caps everything is out", () => {
  expect(L.stateOf([w("Session", "exhausted"), w("Gemini · Weekly", "ok")]).out).toBe(true);
});
