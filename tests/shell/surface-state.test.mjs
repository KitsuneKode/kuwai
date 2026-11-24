import { describe, expect, test } from "bun:test";
import { createSurfaceState, stepSurface, surfaceOutputs } from "../../shell/services/surfaceState.mjs";

describe("surfaceState", () => {
  test("full lifecycle: closed -> opening -> entering -> open -> leaving -> closed", () => {
    let s = createSurfaceState();
    expect(surfaceOutputs(s).mapped).toBe(false);

    let r = stepSurface(s, { type: "open" });
    s = r.state;
    expect(s.phase).toBe("opening");
    expect(surfaceOutputs(s).grabActive).toBe(false);
    expect(surfaceOutputs(s).keyboardFocus).toBe(true);

    r = stepSurface(s, { type: "surfaceMapped", seq: s.seq });
    s = r.state;
    expect(s.phase).toBe("entering");
    expect(r.effects.map(e => e.type)).toEqual(["beginMotion", "scheduleArm"]);

    r = stepSurface(s, { type: "armed", seq: s.seq });
    s = r.state;
    expect(s.phase).toBe("open");
    expect(surfaceOutputs(s).grabActive).toBe(true);

    r = stepSurface(s, { type: "close" });
    s = r.state;
    expect(s.phase).toBe("leaving");
    expect(surfaceOutputs(s).grabActive).toBe(false);
    expect(surfaceOutputs(s).mapped).toBe(true);

    r = stepSurface(s, { type: "foldDone", seq: s.seq });
    s = r.state;
    expect(s.phase).toBe("closed");
    expect(surfaceOutputs(s).mapped).toBe(false);
  });

  test("stale arm or foldDone callbacks from earlier open/close cycles are ignored", () => {
    let s = createSurfaceState();
    let r = stepSurface(s, { type: "open" });
    const firstSeq = r.state.seq;
    s = stepSurface(r.state, { type: "surfaceMapped", seq: firstSeq }).state;
    s = stepSurface(s, { type: "close" }).state;
    const closeSeq = s.seq;
    r = stepSurface(s, { type: "open" });
    s = r.state;
    expect(r.effects[0].reopening).toBe(true);

    const afterStaleArm = stepSurface(s, { type: "armed", seq: firstSeq }).state;
    expect(afterStaleArm.armed).toBe(false);

    const afterStaleFold = stepSurface(s, { type: "foldDone", seq: closeSeq }).state;
    expect(afterStaleFold.phase).toBe("opening");
  });

  test("screenshot capture holds surface open without grab or keyboard focus", () => {
    let s = createSurfaceState();
    s = stepSurface(s, { type: "open" }).state;
    s = stepSurface(s, { type: "surfaceMapped", seq: s.seq }).state;
    s = stepSurface(s, { type: "armed", seq: s.seq }).state;

    const r = stepSurface(s, { type: "grabCleared", capturingTool: true });
    s = r.state;
    expect(surfaceOutputs(s).open).toBe(true);
    expect(surfaceOutputs(s).grabActive).toBe(false);
    expect(surfaceOutputs(s).keyboardFocus).toBe(false);

    const r2 = stepSurface(s, { type: "captureEnded" });
    s = r2.state;
    expect(surfaceOutputs(s).grabActive).toBe(true);
    expect(surfaceOutputs(s).keyboardFocus).toBe(true);
  });

  test("peeking mode never activates focus grab or keyboard focus", () => {
    let s = createSurfaceState();
    s = stepSurface(s, { type: "open", peeking: true }).state;
    s = stepSurface(s, { type: "surfaceMapped", seq: s.seq }).state;
    s = stepSurface(s, { type: "armed", seq: s.seq }).state;
    expect(surfaceOutputs(s).grabActive).toBe(false);
    expect(surfaceOutputs(s).keyboardFocus).toBe(false);
    expect(stepSurface(s, { type: "grabCleared" }).effects).toEqual([]);
  });
});
