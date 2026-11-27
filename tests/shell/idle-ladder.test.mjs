import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { saverAfter, saverAllowed, afterText, fadeLead } from '../../shell/services/idleLadder.mjs';

const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

test('the saver is a step before the fade, and the lock keeps its time', () => {
  expect(saverAfter(3, 300, false)).toBe(180);
  expect(saverAfter(5, 300, false)).toBe(300 - 2 * fadeLead);
  expect(saverAfter(10, 180, false)).toBe(180 - 2 * fadeLead);
  expect(saverAfter(1, 60, false)).toBe(30);
  expect(saverAfter(3, 20, false)).toBe(5);
  expect(saverAfter(3, 10, false)).toBe(1);
  for (const lock of [20, 60, 180, 300, 900]) for (const mins of [1, 3, 5, 10]) {
    const fadeAt = lock > 20 ? lock - fadeLead : lock;
    expect(saverAfter(mins, lock, false)).toBeLessThan(fadeAt);
  }
});

test('under Caffeine, or with no lock, the saver keeps its own minutes', () => {
  expect(saverAfter(10, 300, true)).toBe(600);
  expect(saverAfter(5, 0, false)).toBe(300);
  expect(saverAfter(0, 0, false)).toBe(180);
});

test('always is the default; caffeine only with Caffeine on; off never', () => {
  expect(saverAllowed(undefined, false)).toBe(true);
  expect(saverAllowed('always', false)).toBe(true);
  expect(saverAllowed('caffeine', false)).toBe(false);
  expect(saverAllowed('caffeine', true)).toBe(true);
  expect(saverAllowed('off', true)).toBe(false);
});

test('the wait reads as minutes and seconds', () => {
  expect(afterText(180)).toBe('3 min');
  expect(afterText(270)).toBe('4 min 30 s');
  expect(afterText(30)).toBe('30 s');
});

test('Idle and the screensaver share one ladder; the fade and lock are unchanged', () => {
  const idle = read('shell/services/Idle.qml');
  expect(idle).toMatch(/saverAfter: Ladder\.saverAfter\(Settings\.screensaverMins, lockAfter, Caffeine\.on \|\| !enabled\)/);
  expect(idle).toMatch(/timeout: root\.lockAfter - Ladder\.fadeLead/);
  expect(idle).toMatch(/timeout: root\.lockAfter\n/);
  const saver = read('shell/modules/screensaver/Screensaver.qml');
  expect(saver).toMatch(/readonly property bool allowed: Idle\.saverAllowed/);
  expect(saver).toMatch(/timeout: Idle\.saverAfter/);
  expect(saver).toMatch(/enabled: root\.allowed && !Activities\.voxBusy/);
  expect(saver).toMatch(/\(forced \|\| !Idle\.appHeld\)/);
});

test('a fresh install shows the still wallpaper before the lock; a chosen look is kept', () => {
  const schema = JSON.parse(read('shell/config/settings-schema.json'));
  const key = k => schema.settings.find(e => e.key === k);
  expect(key('screensaverWhen').default).toBe('always');
  expect(key('screensaverStyle').default).toBe('still');
  expect(read('shell/modules/screensaver/Screensaver.qml')).toMatch(/Settings\.screensaverStyle \|\| "still"/);
});
