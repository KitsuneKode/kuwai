import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { plateFor, reads, ground, ratio, grey, linear, zoneOf, cells, brightest } from '../../shell/services/lockPlate.mjs';
import { functions } from '../helpers/qml.mjs';

const cards = { scrim: 0.22, frost: 0.15, tone: 0.067, most: 0.84, inks: [{ alpha: 1, want: 4.5 }, { alpha: 0.5, want: 3 }] };

describe('the plate under the lock cards', () => {
  test('a dark wallpaper needs none', () => {
    expect(plateFor(0, cards)).toBe(0);
    expect(plateFor(0.2, cards)).toBe(0);
  });
  test('the brighter the picture, the denser the plate, never past the most', () => {
    const steps = [0.3, 0.5, 0.7, 0.9, 1].map(b => plateFor(b, cards));
    for (let i = 1; i < steps.length; i++) expect(steps[i]).toBeGreaterThanOrEqual(steps[i - 1]);
    expect(steps[steps.length - 1]).toBeGreaterThan(0.3);
    expect(Math.max(...steps)).toBeLessThanOrEqual(cards.most);
  });
  test('the plate it picks makes every ink read on white snow', () => {
    const p = plateFor(1, cards);
    expect(reads(1, cards, p)).toBe(true);
    expect(reads(1, cards, 0)).toBe(false);
  });
  test('it picks the least plate that reads', () => {
    for (const b of [0.6, 0.8, 1]) {
      const p = plateFor(b, cards);
      if (p > 0) expect(reads(b, cards, p - 0.02)).toBe(false);
    }
  });
  test('the hint, tinted ink without frost, gets its own answer', () => {
    const hint = { scrim: 0.22, frost: 0, tone: 0.067, most: 0.84, inks: [{ alpha: 0.85, tone: grey(0.7), want: 4.5 }] };
    expect(plateFor(0.1, hint)).toBe(0);
    expect(reads(1, hint, plateFor(1, hint))).toBe(true);
    expect(plateFor(1, hint)).toBeGreaterThan(plateFor(1, Object.assign({}, hint, { inks: [{ alpha: 0.85, want: 4.5 }] })));
  });
  test('contrast and grey agree with WCAG', () => {
    expect(ratio(1, 0)).toBeCloseTo(21, 5);
    expect(linear(grey(0.5))).toBeCloseTo(0.5, 6);
    expect(ground(1, { scrim: 0, frost: 0, tone: 0 }, 1)).toBe(0);
  });
});

describe('where the plate looks', () => {
  test('the cards\' box as shares of the screen, clamped', () => {
    expect(zoneOf({ x: 745, y: 497, width: 430, height: 300 }, 1920, 1080)).toEqual({ x: 745 / 1920, y: 497 / 1080, width: 430 / 1920, height: 300 / 1080 });
    const z = zoneOf({ x: 0, y: 1000, width: 0, height: 0 }, 1920, 1080);
    expect(z.width).toBeGreaterThan(0);
    expect(z.y + z.height).toBeLessThanOrEqual(1 + 1e-9);
    expect(zoneOf(null, 0, 0)).toEqual({ x: 0, y: 0, width: 1, height: 1 });
  });
  test('the zone in the 32 x 18 sample is never empty or outside it', () => {
    const r = cells({ x: 0.99, y: 0.99, width: 0.5, height: 0.5 }, 32, 18);
    expect(r.width).toBeGreaterThanOrEqual(1);
    expect(r.x + r.width).toBeLessThanOrEqual(32);
    expect(r.y + r.height).toBeLessThanOrEqual(18);
  });
  test('a few bright pixels count: the 95th percentile of each pixel\'s brightest channel', () => {
    const px = [];
    for (let i = 0; i < 100; i++) px.push(...(i < 6 ? [255, 40, 40, 255] : [20, 20, 20, 255]));
    expect(brightest(px)).toBe(1);
    expect(brightest([])).toBe(0);
  });
});

describe('the lock stack fits above the unlock hint', () => {
  const s = functions('shell/modules/lock/LockNotifs.qml', ['fits'], {});
  test('three when there is room, as before', () => expect(s.fits(5, 1000, 90, 8, 18)).toBe(3));
  test('fewer on a short screen, room kept for "N more"', () => {
    expect(s.fits(3, 200, 90, 8, 18)).toBe(1);
    expect(s.fits(1, 95, 90, 8, 18)).toBe(1);
    expect(s.fits(2, 95, 90, 8, 18)).toBe(0);
  });
  test('none when nothing fits', () => expect(s.fits(4, 20, 90, 8, 18)).toBe(0));
});

test('the lock samples its picture once per change, not every frame', () => {
  const tone = readFileSync(new URL('../../shell/modules/lock/WallTone.qml', import.meta.url), 'utf8');
  expect(tone).not.toMatch(/Timer|FrameAnimation|live:\s*true/);
  expect(tone).toMatch(/onSourceChanged: take\(\)/);
  const view = readFileSync(new URL('../../shell/modules/lock/LockView.qml', import.meta.url), 'utf8');
  expect(view).toMatch(/source: view\.artShown \? lockArt\.source : wall\.source/);
});
