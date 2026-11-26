import { describe, expect, test } from "bun:test";
import { chordOf, canon, canonLive, conflict, groupsOf, caps } from "../../shell/services/keychord.mjs";

const META = 0x10000000, CTRL = 0x04000000, ALT = 0x08000000, SHIFT = 0x02000000;
const Key = { E: 0x45, One: 0x31, Exclam: 0x21, Slash: 0x2f, Question: 0x3f, F7: 0x01000036, Super: 0x01000053, Return: 0x01000004, Left: 0x01000012, Tab: 0x01000001, VolUp: 0x01000072 };

const palette = [
  { id: "b1", kind: "bind", group: "Launch", text: "Files", keys: "SUPER + E", aid: "SUPER+E", def: "SUPER + E", custom: false, fixed: false },
  { id: "b2", kind: "bind", group: "Launch", text: "Terminal", keys: "SUPER + T", aid: "SUPER+T", def: "SUPER + T", custom: false, fixed: false },
  { id: "b3", kind: "bind", group: "Workspaces", text: "Workspace 1", keys: "SUPER + 1", aid: "SUPER+CODE:10", def: "SUPER + 1", custom: false, fixed: false },
  { id: "b4", kind: "bind", group: "Dictation", text: "Dictate while held", keys: "F9", aid: "F9", def: "F9", custom: false, fixed: true },
  { id: "b5", kind: "bind", group: "Windows|Focus", text: "Focus left", keys: "", aid: "SUPER+LEFT", def: "SUPER + left", custom: true, fixed: false },
  { id: "f:x", kind: "feature", group: "Features", text: "A feature" }
];
const live = [
  { modmask: 64, key: "E", keycode: 0, submap: "", description: "[Launch] Files" },
  { modmask: 64, key: "", keycode: 10, submap: "", description: "[Workspaces] Workspace 1" },
  { modmask: 68, key: "N", keycode: 0, submap: "", description: "" },
  { modmask: 68, key: "E", keycode: 0, submap: "voxtype_suppress", description: "" },
  { modmask: 64, key: "mouse:272", keycode: 0, submap: "", mouse: true, description: "[Windows|Move] Drag to move" }
];

describe("a key press as Hyprland's chord", () => {
  test("letters by name, modifiers in one order", () => {
    expect(chordOf(Key.E, META | SHIFT | CTRL)).toEqual({ keys: "SUPER + CTRL + SHIFT + E", canon: "SUPER+CTRL+SHIFT+E", why: "" });
  });
  test("a digit by its keycode, so it holds on AZERTY; shifted, too", () => {
    expect(chordOf(Key.One, META, 10).keys).toBe("SUPER + code:10");
    expect(chordOf(Key.Exclam, META | SHIFT, 10).keys).toBe("SUPER + SHIFT + code:10");
    expect(chordOf(Key.One, META).keys).toBe("SUPER + code:10");
  });
  test("shifted punctuation is named by its key", () => {
    expect(chordOf(Key.Question, META | SHIFT).keys).toBe("SUPER + SHIFT + slash");
  });
  test("a modifier alone keeps listening", () => {
    expect(chordOf(Key.Super, META)).toBeNull();
  });
  test("a plain key needs a modifier, an F-key doesn't", () => {
    expect(chordOf(Key.E, 0).why).toBe("Add Super, Ctrl or Alt");
    expect(chordOf(Key.E, SHIFT).why).toBe("Add Super, Ctrl or Alt");
    expect(chordOf(Key.Tab, 0).why).toBe("Add Super, Ctrl or Alt");
    expect(chordOf(Key.F7, 0)).toEqual({ keys: "F7", canon: "F7", why: "" });
    expect(chordOf(Key.Left, ALT).keys).toBe("ALT + left");
  });
  test("a key with no name says so", () => {
    expect(chordOf(Key.VolUp, META).why).toBe("That key can't be a shortcut");
  });
});

describe("one spelling per chord", () => {
  test("order and digits", () => {
    expect(canon("SHIFT + SUPER + 1")).toBe(canon("SUPER + SHIFT + code:10"));
    expect(canon("SUPER + 0")).toBe("SUPER+CODE:19");
    expect(canon("super + e")).toBe("SUPER+E");
  });
  test("a live bind meets its palette entry", () => {
    expect(canonLive(live[0])).toBe(canon("SUPER + E"));
    expect(canonLive(live[1])).toBe(canon("SUPER + 1"));
    expect(canonLive(live[2])).toBe("SUPER+CTRL+N");
  });
});

describe("who has the chord", () => {
  test("nobody", () => expect(conflict(canon("SUPER + CTRL + ALT + E"), "SUPER+E", palette, live)).toBeNull());
  test("the action itself", () => expect(conflict(canon("SUPER + E"), "SUPER+E", palette, live).kind).toBe("same"));
  test("another of kuwai's actions: it can be moved off", () => {
    const c = conflict(canon("SUPER + E"), "SUPER+T", palette, live);
    expect(c.kind).toBe("kuwai");
    expect(c.entry.aid).toBe("SUPER+E");
  });
  test("a workspace key, however it was pressed", () => {
    expect(conflict(canon("SUPER + code:10"), "SUPER+T", palette, live).entry.text).toBe("Workspace 1");
  });
  test("your own config's bind: it can't be", () => {
    expect(conflict(canon("SUPER + CTRL + N"), "SUPER+T", palette, live)).toEqual({ kind: "other", entry: null, text: "" });
  });
  test("a hold key: it can't be", () => expect(conflict(canon("F9"), "SUPER+T", palette, live).kind).toBe("other"));
  test("a submap's bind isn't in the way", () => expect(conflict(canon("SUPER + CTRL + E"), "SUPER+T", palette, live)).toBeNull());
  test("an action left without keys holds nothing", () => expect(conflict("", "SUPER+T", palette, live)).toBeNull());
});

describe("the list", () => {
  test("groups in the panel's order, features left out, sub-groups kept", () => {
    const g = groupsOf(palette, "");
    expect(g.map(x => x.group)).toEqual(["Launch", "Windows", "Workspaces", "Dictation"]);
    expect(g[1].items[0].sub).toBe("Focus");
  });
  test("every word of the filter", () => {
    expect(groupsOf(palette, "launch term").map(x => x.items.map(i => i.text))).toEqual([["Terminal"]]);
    expect(groupsOf(palette, "super left").map(x => x.group)).toEqual(["Windows"]);
  });
  test("caps", () => {
    expect(caps("SUPER + SHIFT + code:10")).toEqual(["Super", "Shift", "1"]);
    expect(caps("CTRL + ALT + bracketleft")).toEqual(["Ctrl", "Alt", "["]);
    expect(caps("")).toEqual([]);
  });
});
