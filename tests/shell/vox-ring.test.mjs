import { describe, expect, test } from 'bun:test';
import { listen, logical, place, quiet } from '../../shell/modules/voxtype/voxRing.mjs';

const look = { border: 2, rounding: 18, gap: 3, stroke: 3 };
const dp = { id: 0, name: 'DP-3', x: 1920, y: 0, width: 2560, height: 1440, scale: 1, transform: 0, reserved: [0, 36, 0, 0],
  activeWorkspace: { id: 12, name: '12' }, specialWorkspace: { name: '' } };
const edp = { id: 1, name: 'eDP-1', x: 0, y: 360, width: 2560, height: 1440, scale: 4 / 3, transform: 0, reserved: [0, 36, 0, 0],
  activeWorkspace: { id: 1, name: '1' }, specialWorkspace: { name: '' } };
const win = (over) => ({ address: '0xa', mapped: true, hidden: false, monitor: 0, fullscreen: 0,
  workspace: { id: 12, name: '12' }, at: [1937, 48], size: [2526, 1380], ...over });

describe('where the dictation ring goes', () => {
  test('a tiled window with gaps: just outside it, concentric', () => {
    const b = place('0xa', [win()], [dp], look);
    expect(b).toMatchObject({ monitor: 'DP-3', inside: false, x: 9, y: 40, w: 2542, h: 1396, radius: 26 });
    expect(b.win).toEqual({ x: 17, y: 48, w: 2526, h: 1380 });
  });
  test('maximised (fullscreen 1): inside its edge, over its border, never gone', () => {
    const b = place('0xa', [win({ fullscreen: 1, at: [1920, 36], size: [2560, 1404] })], [dp], look);
    expect(b).toMatchObject({ inside: true, x: 0, y: 34, w: 2560, h: 1406, radius: 20 });
  });
  test('fullscreen (2 or 3): the whole screen, square, inside', () => {
    for (const fs of [2, 3]) {
      const b = place('0xa', [win({ fullscreen: fs, at: [1920, 0], size: [2560, 1440] })], [dp], look);
      expect(b).toMatchObject({ inside: true, x: 0, y: 0, w: 2560, h: 1440, radius: 0 });
    }
  });
  test('no room under the bar or at the screen edge: inside', () => {
    expect(place('0xa', [win({ at: [1921, 40] })], [dp], look).inside).toBe(true);
    expect(place('0xa', [win({ at: [1937, 48], size: [2540, 1380] })], [dp], look).inside).toBe(true);
  });
  test('a scaled screen is measured in logical pixels', () => {
    expect(logical(edp)).toEqual({ w: 1920, h: 1080 });
    expect(logical({ width: 2560, height: 1440, scale: 1, transform: 1 })).toEqual({ w: 1440, h: 2560 });
    const b = place('0xa', [win({ monitor: 1, workspace: { id: 1, name: '1' }, at: [12, 408], size: [1896, 1020] })], [edp], look);
    expect(b).toMatchObject({ monitor: 'eDP-1', inside: false, x: 4, y: 40, w: 1912, h: 1036 });
  });
  test('a window nobody sees has no ring: hidden scratchpad, another workspace, unmapped, unknown', () => {
    const scratch = win({ workspace: { name: 'special:special' } });
    expect(place('0xa', [scratch], [dp], look)).toBeNull();
    expect(place('0xa', [scratch], [{ ...dp, specialWorkspace: { name: 'special:special' } }], look)).not.toBeNull();
    expect(place('0xa', [win({ workspace: { id: 3, name: '3' } })], [dp], look)).toBeNull();
    expect(place('0xa', [win({ mapped: false })], [dp], look)).toBeNull();
    expect(place('0xb', [win()], [dp], look)).toBeNull();
    expect(place('0xa', null, null, look)).toBeNull();
  });
});

describe('the voice on the ring', () => {
  const run = (peak, ms) => {
    let s = quiet();
    for (let t = 0; t < ms; t += 45) s = listen(s, peak, 45);
    return s;
  };
  test('speech on a quiet chain (-50 dBFS over a -60 room) lights it, where sqrt(peak) gave 0.08', () => {
    let s = run(0.001, 900);
    for (let t = 0; t < 300; t += 45) s = listen(s, 0.00316, 45);
    expect(s.glow).toBeGreaterThan(0.45);
  });
  test('loud speech fills it; the room alone stays dim', () => {
    let s = run(0.001, 900);
    expect(s.glow).toBeLessThan(0.15);
    for (let t = 0; t < 300; t += 45) s = listen(s, 0.05, 45);
    expect(s.glow).toBeGreaterThan(0.85);
  });
  test('digital silence (RNNoise zeros) is dark and never moves the floor', () => {
    const s = run(0, 2000);
    expect(s.glow).toBe(0);
    expect(s.noise).toBe(quiet().noise);
  });
  test('it falls back slower than it rises', () => {
    let s = run(0.001, 900);
    s = listen(s, 0.05, 45);
    const up = s.glow;
    s = listen(s, 0.001, 45);
    expect(up).toBeGreaterThan(0.5);
    expect(s.glow).toBeGreaterThan(up * 0.7);
  });
});
