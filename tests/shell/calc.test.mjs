// The launcher's calculator (shell/services/calc.js), from its own source.
//   bun test tests/shell/calc.test.mjs
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const src = readFileSync(new URL("../../shell/services/calc.js", import.meta.url), "utf8").replace(/^\.pragma library\s*$/m, "");
const { evaluate, looksLikeMath } = new Function(src + "\nreturn { evaluate, looksLikeMath };")();
const fx = { time: 0, rates: { USD: 1, JPY: 158.18, EUR: 0.92, INR: 83.1, GBP: 0.79 } };
const v = (q) => (evaluate(q, fx) || {}).value;

describe("arithmetic", () => {
  test("12 * 7", () => expect(v("12 * 7")).toBe("84"));
  test("12 x 7", () => expect(v("12 x 7")).toBe("84"));
  test("powers and brackets", () => expect(v("(3 + 4)^2")).toBe("49"));
  test("= prefix", () => expect(v("= 2 + 2")).toBe("4"));
  test("thousands", () => expect(v("1,000 + 5")).toBe("1,005"));
  test("100 + 10/100", () => expect(v("100 + 10/100")).toBe("100.1"));
});

describe("percent, as a calculator does", () => {
  test("100 + 10%", () => expect(v("100 + 10%")).toBe("110"));
  test("250 - 20%", () => expect(v("250 - 20%")).toBe("200"));
  test("12 + 8 * 90 + 10%", () => expect(v("12 + 8 * 90 + 10%")).toBe("805.2"));
  test("15% of 80", () => expect(v("15% of 80")).toBe("12"));
});

describe("units", () => {
  test("10 km to miles", () => expect(v("10 km to miles")).toBe("6.2137 miles"));
  test("72 f in c", () => expect(v("72 f in c")).toBe("22.2222 °C"));
  test("3 gib to mb", () => expect(v("3 gib to mb")).toBe("3,221.23 mb"));
  test("mixed, in the first unit", () => expect(v("6 mi + 376 yd + 4.78 in")).toBe("6.2137 mi"));
  test("mixed, to a unit", () => expect(v("6 mi + 376 yd + 4.78 in to m")).toBe("10,000 m"));
  test("mixed dimensions refuse", () => expect(evaluate("6 mi + 3 kg", fx)).toBe(null));
});

describe("currencies", () => {
  test("20 usd to yen", () => expect(v("20 usd to yen")).toBe("3,163.6 JPY"));
  test("$20 in rupees", () => expect(v("$20 in rupees")).toBe("1,662 INR"));
  test("5€ to £", () => expect(v("5€ to £")).toBe("4.2935 GBP"));
  test("no rates yet: pending", () => expect(evaluate("20 usd to eur", null).pending).toBe(true));
});

describe("not math", () => {
  for (const q of ["firefox", "kitty", "settings", "note buy milk", ""])
    test(JSON.stringify(q), () => {
      expect(evaluate(q, fx)).toBe(null);
      expect(looksLikeMath(q)).toBe(false);
    });
  test("asks qalc for sqrt(2)", () => expect(looksLikeMath("sqrt(2) * 3")).toBe(true));
});
