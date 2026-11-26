import { expect, test } from "bun:test";
import { functions } from "../helpers/qml.mjs";

const look = (accent, extra = {}) => JSON.stringify({ schema: 1, role: { accent, bg: "#0d0d0d" }, mode: "dark", ...extra });

function theme(lookText, dcol) {
  const s = { accent: "blue", colorMode: 0, themeName: "", Qt: { color: c => c },
    kuwaiLook: { ok: lookText !== null, text: () => lookText }, themeDcol: { ok: false }, themeKitty: { ok: false },
    wallDcol: { ok: !!dcol, text: () => dcol }, vivid: c => "vivid " + c };
  return functions("shell-auth/config/Theme.qml", ["lookAccent", "dcolAccent", "recolor"], s);
}

test("the password prompt takes the kuwai theme's accent, as the shell does", () => {
  const t = theme(look("#d45e73"), 'dcol_1xa7="336699"');
  t.recolor();
  expect(t.accent).toBe("#d45e73");
});

test("without a kuwai look it keeps HyDE's wallpaper colour", () => {
  const t = theme(null, 'dcol_1xa7="336699"');
  t.recolor();
  expect(t.accent).toBe("vivid #336699");
});

test("a look file that isn't one is not a colour", () => {
  for (const bad of ["{", look("red"), look("#12345"), JSON.stringify({ schema: 2, role: { accent: "#ffffff" } })]) {
    const t = theme(bad, 'dcol_1xa7="336699"');
    t.recolor();
    expect(t.accent).toBe("vivid #336699");
  }
});
