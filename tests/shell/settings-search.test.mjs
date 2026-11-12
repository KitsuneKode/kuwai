// Finding a setting (shell/services/settingsSearch.js), against the real
// Settings panel's source, so a renamed row shows up here.
//   bun test tests/shell/settings-search.test.mjs
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const lib = readFileSync(new URL("../../shell/services/settingsSearch.js", import.meta.url), "utf8").replace(/^\.pragma library\s*$/m, "");
const { parseRows, search } = new Function(lib + "\nreturn { parseRows, search };")();
const panel = readFileSync(new URL("../../shell/modules/island/SettingsPanel.qml", import.meta.url), "utf8");
const indexSrc = readFileSync(new URL("../../shell/services/SettingsIndex.qml", import.meta.url), "utf8");

// The page map and sections, as SettingsIndex declares them.
const pages = Function("return " + /readonly property var pages:\s*\((\{[^}]*\})\)/.exec(indexSrc)[1])();
const sections = [...indexSrc.matchAll(/\{ id: "(\w+)", keys: "([^"]*)", label: "([^"]+)"/g)].map(m => ({ id: m[1], keys: m[2], label: m[3] }));
const rows = parseRows(panel, pages);
const first = q => search(sections, rows, q)[0];

describe("the index", () => {
  test("every page in the panel is mapped", () => {
    const ids = [...panel.matchAll(/\bid:\s*(\w+Page)\b/g)].map(m => m[1]).filter(id => id !== "kbPage");
    for (const id of ids) expect(pages[id]).toBeTruthy();
  });
  test("reads most of the panel's rows", () => expect(rows.length).toBeGreaterThan(55));
  test("an option's label isn't taken for the row's", () => expect(rows.some(r => r.label === "Waybar")).toBe(false));
  test("a row knows its group", () => expect(rows.find(r => r.label === "Hover delay").group).toBe("On hover"));
  test("a row knows its page", () => expect(rows.find(r => r.label === "Hover delay").page).toBe("bar"));
});

describe("searching", () => {
  test("a row by its name", () => expect(first("hover delay").row.label).toBe("Hover delay"));
  test("a row by a word of its detail", () => expect(search(sections, rows, "waybar").some(r => r.row && r.row.label === "Top bar")).toBe(true));
  test("a row by one of its choices", () => expect(search(sections, rows, "notch").some(r => r.row && r.row.label === "Shape")).toBe(true));
  test("a page by its name comes first", () => {
    const r = first("keyboard");
    expect(r.section.id).toBe("keyboard");
    expect(r.row).toBe(null);
  });
  test("a page by its keywords", () => expect(search(sections, rows, "hypridle").some(r => r.section.id === "power")).toBe(true));
  test("every word must match", () => expect(search(sections, rows, "hover zzzz")).toEqual([]));
  test("one letter isn't a search", () => expect(search(sections, rows, "a")).toEqual([]));
  test("case doesn't matter", () => expect(first("HOVER DELAY").row.label).toBe("Hover delay"));
  test("capped", () => expect(search(sections, rows, "the", 5).length).toBeLessThanOrEqual(5));
});
