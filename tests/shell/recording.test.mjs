import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";

// Execute the actual FileView load handler; the file reader and clock are boundaries.
function load(path, value) {
  const source = readFileSync(new URL("../../shell/services/Clipboard.qml", import.meta.url), "utf8");
  const start = source.indexOf("onLoaded:", source.indexOf(path));
  const open = source.indexOf("{", start);
  let depth = 1, end = open;
  while (depth && ++end < source.length) {
    if (source[end] === "{") depth++;
    if (source[end] === "}") depth--;
  }
  const root = { recSince: 0, recTarget: "", recSaved: null };
  new Function("root", "text", "savedClear", "Date", source.slice(open + 1, end))(
    root, () => value, { restart() {} }, { now: () => 1_000_000 },
  );
  return root;
}

test("recording state preserves the target after a path containing spaces", () => {
  expect(load("path: root.recState\n", "123\t999\t/videos with spaces/a.mp4\tDP-1\n")).toMatchObject({ recSince: 999, recTarget: "DP-1" });
});

test("saved recordings preserve complete paths and thumbnails", () => {
  expect(load('path: root.recState + "-saved"', "999\t2\t/videos with spaces/a.mp4\t/thumb with spaces.jpg\n").recSaved)
    .toEqual({ at: 999, duration: 2, path: "/videos with spaces/a.mp4", thumb: "/thumb with spaces.jpg" });
});

test("malformed and non-finite recording times cannot poison UI bindings", () => {
  for (const value of ["123 invalid /x DP-1", "123 Infinity /x DP-1", "123 -1 /x DP-1", "bad"]) {
    expect(load("path: root.recState\n", value)).toMatchObject({ recSince: 0, recTarget: "" });
  }
});

test("expired and future-dated saved files do not display stale success", () => {
  for (const value of ["900 2 /x /thumb", "1005 2 /x /thumb", "999 -3 /x /thumb", "999 Infinity /x /thumb"]) {
    expect(load('path: root.recState + "-saved"', value).recSaved).toBeNull();
  }
});

test("legacy space-delimited state remains readable", () => {
  expect(load("path: root.recState\n", "123 999 /videos/a.mp4 DP-1")).toMatchObject({ recSince: 999, recTarget: "DP-1" });
});
