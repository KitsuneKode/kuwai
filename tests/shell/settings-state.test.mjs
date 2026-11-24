import { describe, expect, test } from "bun:test";
import { createSettingsState, stepSettings } from "../../shell/config/settingsState.mjs";

describe("settingsState generation ordering", () => {
  test("stale disk read after a local enqueue never overwrites the newer write", () => {
    let s = createSettingsState();
    s = stepSettings(s, { type: "readCompleted", ok: true, text: "{}" }).state;
    expect(s.loaded).toBe(true);

    s = stepSettings(s, { type: "fileChanged" }).state;
    s = stepSettings(s, { type: "beginRead" }).state;
    expect(s.readBusy).toBe(true);

    s = stepSettings(s, { type: "enqueue", patch: { key: "bar", value: "island" } }).state;

    const r = stepSettings(s, { type: "readCompleted", ok: true, text: '{"bar":"waybar"}' });
    s = r.state;
    expect(r.effects.some(e => e.type === "acceptDocument")).toBe(false);
    expect(s.needsRead).toBe(true);
    expect(r.effects.some(e => e.type === "drain")).toBe(true);
  });

  test("queued second write prevents first write completion from accepting intermediate output early", () => {
    let s = createSettingsState();
    s = stepSettings(s, { type: "readCompleted", ok: true, text: "{}" }).state;
    s = stepSettings(s, { type: "enqueue", patch: { key: "bar", value: "island" } }).state;
    s = stepSettings(s, { type: "beginWrite" }).state;
    s = stepSettings(s, { type: "enqueue", patch: { key: "clock24", value: false } }).state;

    const r1 = stepSettings(s, { type: "writeCompleted", ok: true, text: '{"bar":"island"}' });
    s = r1.state;
    expect(r1.effects.some(e => e.type === "acceptDocument")).toBe(false);
    expect(r1.effects.some(e => e.type === "drain")).toBe(true);

    s = stepSettings(s, { type: "beginWrite" }).state;
    const r2 = stepSettings(s, { type: "writeCompleted", ok: true, text: '{"bar":"island","clock24":false}' });
    expect(r2.effects.some(e => e.type === "acceptDocument")).toBe(true);
    expect(r2.effects.some(e => e.type === "scheduleRead")).toBe(true);
  });
});
