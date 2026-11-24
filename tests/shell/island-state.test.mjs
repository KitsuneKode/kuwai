import { describe, expect, test } from "bun:test";
import { MAX_DWELL_RETRIES, canGrow, createIslandState, stepIsland } from "../../shell/modules/island/state.mjs";

describe("island state machine", () => {
  test("pushed never stays stuck after leaving or opening a panel or peeking", () => {
    let s = createIslandState();
    s = stepIsland(s, { type: "hoverSync", hovered: true, compact: false });
    s = stepIsland(s, { type: "pushBack" });
    expect(s.pushed).toBe(true);
    expect(canGrow(s, {})).toBe(false);

    s = stepIsland(s, { type: "hoverSync", hovered: false, compact: false });
    expect(s.pushed).toBe(false);

    s = stepIsland(s, { type: "hoverSync", hovered: true, compact: false });
    expect(canGrow(s, {})).toBe(true);

    s = stepIsland(s, { type: "pushBack" });
    s = stepIsland(s, { type: "panelChanged", panelHere: true });
    expect(s.pushed).toBe(false);

    s = stepIsland(s, { type: "panelChanged", panelHere: false });
    s = stepIsland(s, { type: "pushBack" });
    s = stepIsland(s, { type: "peekChanged", peeked: true });
    expect(s.pushed).toBe(false);
    expect(s.grown).toBe(true);
  });

  test("nearDwell bounds retries instead of retriggering forever", () => {
    let s = createIslandState();
    for (let i = 0; i < MAX_DWELL_RETRIES + 5; i++) {
      s = stepIsland(s, { type: "nearDwellTick", nearHovered: true, proximityAvailable: true, edgeSettled: false });
    }
    expect(s.near).toBe(false);
    expect(s.dwellRetries).toBe(MAX_DWELL_RETRIES);

    s = stepIsland(s, { type: "nearDwellTick", nearHovered: true, proximityAvailable: true, edgeSettled: true });
    expect(s.near).toBe(true);
    expect(s.dwellRetries).toBe(0);
  });

  test("stale arm tick from an earlier panel open cannot arm after close or reopen", () => {
    let s = createIslandState();
    s = stepIsland(s, { type: "panelChanged", panelHere: true });
    const firstSeq = s.armSeq;
    s = stepIsland(s, { type: "panelChanged", panelHere: false });
    s = stepIsland(s, { type: "panelChanged", panelHere: true });

    s = stepIsland(s, { type: "armTick", seq: firstSeq });
    expect(s.armed).toBe(false);

    s = stepIsland(s, { type: "armTick", seq: s.armSeq });
    expect(s.armed).toBe(true);
  });
});
