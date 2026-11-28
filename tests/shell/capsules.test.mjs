import { describe, expect, test } from "bun:test";
import { safeRun } from "../../shell/services/capsules.mjs";

const bin = "/usr/local/share/kuwai/bin";

describe("capsule run commands from runtime json", () => {
  test("kuwai subcommands only", () => {
    expect(safeRun([bin + "/kuwai", "notifs", "mute-on"], bin)).toEqual([bin + "/kuwai", "notifs", "mute-on"]);
    expect(safeRun(["kuwai", "bar", "island"], bin)).toEqual(["kuwai", "bar", "island"]);
    expect(safeRun(["notify-send", "hi"], bin)).toBeNull();
    expect(safeRun([bin + "/kuwai", "sh", "-c", "rm"], bin)).toBeNull();
  });
  test("kuwai-ext capsule only", () => {
    expect(safeRun([bin + "/kuwai-ext", "capsule", "clear", "x"], bin)).toEqual([bin + "/kuwai-ext", "capsule", "clear", "x"]);
    expect(safeRun([bin + "/kuwai-ext", "query", "gh", "x"], bin)).toBeNull();
  });
});