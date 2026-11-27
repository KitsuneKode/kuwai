import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import * as Otp from '../../shell/services/otp.mjs';
import { hidden } from '../../shell/services/notifPrivacy.mjs';
import { functions } from '../helpers/qml.mjs';

function stack(items, o) {
  const ctx = Object.assign({ sharing: false, place: 'lock', mode: 'lock', privateSenders: '' }, o);
  const removed = [];
  const Notifs = {
    items,
    otpOf: Otp.otpOf, otpLikely: Otp.otpLikely, codeShaped: Otp.codeShaped,
    lockHidden: i => hidden(i, ctx),
    remove(i) { removed.push(i); Notifs.items = Notifs.items.filter(x => x !== i); }
  };
  const s = functions('shell/modules/lock/LockNotifs.qml', ['key', 'isCode', 'guarded', 'members', 'clear', 'preview', 'heading'], { Notifs });
  s.removed = removed;
  s.Notifs = Notifs;
  return s;
}

const build = { nid: 1, time: 1, app: 'CI', title: 'Build failed', body: '2 tests', groupKey: 'ci' };
const chat = { nid: 2, time: 2, app: 'Signal', title: 'Anna', body: 'lunch at 12?', groupKey: 'anna' };
const code = { nid: 3, time: 3, app: 'Bank', title: 'Sign in', body: 'Your code is 482913', groupKey: 'bank' };
const pin = { nid: 4, time: 4, app: 'CI', title: 'Deploy', body: 'Your new password is hunter2', groupKey: 'ci' };

describe('clearing a notification from the lock screen', () => {
  test('an ordinary one clears, as before', () => {
    const s = stack([build, chat]);
    expect(s.clear('ci')).toBe(true);
    expect(s.removed).toEqual([build]);
  });
  test('a message the lock hides needs an unlock first', () => {
    const s = stack([build, chat]);
    expect(s.clear('anna')).toBe(false);
    expect(s.removed).toEqual([]);
  });
  test('a code needs an unlock first, wherever it came from', () => {
    const s = stack([code]);
    expect(s.guarded([code])).toBe(true);
    expect(s.clear('bank')).toBe(false);
  });
  test('a conversation with one hidden message in it stays whole', () => {
    const s = stack([build, pin]);
    expect(s.clear('ci')).toBe(false);
    expect(s.Notifs.items.length).toBe(2);
  });
  test('while the screen is shared, nothing is cleared from the lock', () => {
    const s = stack([build], { sharing: true });
    expect(s.clear('ci')).toBe(false);
  });
  test('with messages shown in full on the lock, a chat clears like the rest', () => {
    const s = stack([chat], { mode: 'never' });
    expect(s.clear('anna')).toBe(true);
  });
  test('the card says why in plain words', () => {
    const s = stack([chat, code]);
    expect(s.preview(chat)).toBe('Message hidden · unlock to read or clear');
    expect(s.preview(code)).toBe('Code hidden · unlock to see or clear');
    expect(s.preview(build)).toBe('2 tests');
  });
});

test('the swipe and Delete both ask the same guard', () => {
  const src = readFileSync(new URL('../../shell/modules/lock/LockNotifs.qml', import.meta.url), 'utf8');
  expect(src).toMatch(/held: card\.guarded/);
  expect(src).toMatch(/onLeaving: stack\.clear\(card\.k\)/);
  expect(src).toMatch(/Key_Delete\) \{\s*stack\.clear\(card\.k\);/);
  expect(src.match(/Notifs\.remove\(/g).length).toBe(1);
  const swipe = readFileSync(new URL('../../shell/components/SwipeAway.qml', import.meta.url), 'utf8');
  expect(swipe).toMatch(/if \(held\) \{ refused\(\); return; \}/);
  expect(swipe).toMatch(/held \? Theme\.swipeDamp\(translation\.x\) : translation\.x/);
});
