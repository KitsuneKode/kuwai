import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { functions } from '../helpers/qml.mjs';
import * as Outcome from '../../shell/services/wallOutcome.mjs';

const shown = (a, b) => `: eDP-1: 1920x1080, scale: 1, currently displaying: image: ${a}\n: DP-3: 2560x1440, scale: 1, currently displaying: image: ${b}\n`;

test('only a picture that stayed the same on every screen counts as not changed', () => {
  const before = Outcome.parseShown(shown('/w/old.jpg', '/w/old.jpg'));
  expect(before).toEqual({ 'eDP-1': '/w/old.jpg', 'DP-3': '/w/old.jpg' });
  expect(Outcome.unchanged(before, Outcome.parseShown(shown('/w/old.jpg', '/w/old.jpg')), '/w/new.jpg')).toBe(true);
  expect(Outcome.unchanged(before, Outcome.parseShown(shown('/w/new.jpg', '/w/new.jpg')), '/w/new.jpg')).toBe(false);
  expect(Outcome.unchanged(before, Outcome.parseShown(shown('/w/old.jpg', '/w/new.jpg')), '/w/new.jpg')).toBe(false);
  expect(Outcome.unchanged(before, Outcome.parseShown(shown('/w/other.jpg', '/w/old.jpg')), '/w/new.jpg')).toBe(false);
});

test('a doubt is never a failure: nothing known, awww gone, or the same picture picked again', () => {
  const before = { 'DP-3': '/w/old.jpg' };
  expect(Outcome.unchanged({}, before, '/w/new.jpg')).toBe(false);
  expect(Outcome.unchanged(before, {}, '/w/new.jpg')).toBe(false);
  expect(Outcome.unchanged(before, before, '/w/old.jpg')).toBe(false);
});

test('the sentence is plain: no helper, status or path', () => {
  for (const why of ['', 'unreadable']) {
    const s = Outcome.sentence(why);
    expect(s).not.toMatch(/awww|kuwai|hyde|exit|\/|status|code/i);
    expect(s.length).toBeLessThanOrEqual(40);
  }
});

function wallfx() {
  const said = [];
  const s = functions('shell/services/WallFx.qml', ['verify', 'verified', 'parse'], {
    Outcome, toLive: false, next: '/w/new.jpg', shownBefore: { 'DP-3': '/w/old.jpg' }, failure: '', lastRun: 'revealed',
    verifier: { path: '', before: {}, why: '', tries: 0, running: false },
    verifyLater: { restarts: 0, restart() { this.restarts++; } },
    Moments: { show: m => said.push(m.label) }, Theme: { textPrimary: 'white' },
  });
  return { s, said };
}

test('a change that left the old picture on screen says so once, after a few looks', () => {
  const { s, said } = wallfx();
  s.verify();
  expect(s.verifier.path).toBe('/w/new.jpg');
  for (let i = 0; i < 3; i++) s.verified(': DP-3: x, image: /w/old.jpg\nkuwai-wanted /w/new.jpg\n');
  expect(said).toEqual([]);
  s.verified(': DP-3: x, image: /w/old.jpg\nkuwai-wanted /w/new.jpg\n');
  expect(said).toEqual(['The wallpaper couldn\'t be changed']);
});

test('a change that landed, a live one, or one with nothing known says nothing', () => {
  const { s, said } = wallfx();
  s.verify();
  s.verified(': DP-3: x, image: /w/new.jpg\nkuwai-wanted /w/new.jpg\n');
  expect(said).toEqual([]);
  const live = wallfx();
  live.s.toLive = true; live.s.verify();
  expect(live.s.verifyLater.restarts).toBe(0);
  const blind = wallfx();
  blind.s.shownBefore = {}; blind.s.verify();
  expect(blind.s.verifyLater.restarts).toBe(0);
});

test('every way a change ends is checked, and an unreadable picture is named', () => {
  const qml = readFileSync(new URL('../../shell/services/WallFx.qml', import.meta.url), 'utf8');
  expect(qml).toMatch(/if \(start\) start\(\);\n\s*verify\(\);/);
  expect(qml).toMatch(/lastRun = "forced: " \+ why;\n\s*verify\(\);/);
  expect(qml).toMatch(/cancelTransition\(\);\n\s*verify\(\);/);
  expect(qml).toMatch(/status === Image\.Error\) \{ root\.unreadable\(root\.next\)/);
  expect(qml).toMatch(/"sh", "-c", 'awww query[^']*realpath -e -- "\$1"[^']*', "sh", path\]/);
  expect(Outcome.sentence('unreadable')).toBe('That picture couldn\'t be opened');
});
