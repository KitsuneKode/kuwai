import { describe, expect, test } from 'bun:test';
import { repeats, t3Settled, expired, sameMessage, olderTwins } from '../../shell/services/notifTidy.mjs';

const now = Date.parse('2026-11-21T12:00:00Z');
const min = 60000;
const n = (o) => Object.assign({ app: 'App', title: 't', body: 'b', status: '', time: now - min, urgency: 1, popup: false, discard: false }, o);

describe('the same message again replaces the row before it', () => {
  test('identical app, title, body and status: the older rows go', () => {
    const a = n({ app: 'voxtype', title: 'voxtype', body: 'NVIDIA driver updated; reboot to finish.' });
    const b = n({ app: 'voxtype', title: 'voxtype', body: 'NVIDIA driver updated;  reboot to finish.' });
    const other = n({ app: 'voxtype', title: 'voxtype', body: 'voxtype-bin moved files' });
    const fresh = n({ app: 'voxtype', title: 'voxtype', body: 'NVIDIA driver updated; reboot to finish.', time: now });
    expect(repeats([fresh, a, b, other], fresh)).toEqual([a, b]);
  });
  test('a different app, a toast still on screen, or one already leaving: kept', () => {
    const fresh = n({ time: now });
    expect(repeats([fresh, n({ app: 'Other' }), n({ popup: true }), n({ discard: true })], fresh)).toEqual([]);
    expect(sameMessage(n({ status: 'Thread completed' }), n({ status: 'Usage limit reached' }))).toBe(false);
  });
});

describe('T3 Code: a thread you have opened is no longer news', () => {
  const t3 = (items, rawFinished) => ({ alive: true, items, rawItems: items, rawFinished: rawFinished ?? items.filter(i => i.status === 'completed' || i.status === 'failed').length });
  const done = n({ app: 'T3 Code', title: 'Codebase Audit: Speed, Consistency, SEO', body: '', status: 'Thread completed', time: now - 3 * 60 * min });
  test('opened in T3 (not listed any more): the notification goes', () => {
    expect(t3Settled([done], t3([]), now)).toEqual([done]);
  });
  test('still unopened, or working again: it stays', () => {
    expect(t3Settled([done], t3([{ title: 'Codebase Audit: Speed, Consistency, SEO', status: 'completed', at: '2026-11-21T09:00:00Z' }]), now)).toEqual([]);
    expect(t3Settled([done], t3([{ title: 'codebase audit: speed, consistency, seo', status: 'running', at: '2026-11-21T11:59:00Z' }]), now)).toEqual([]);
  });
  test('T3 closed, a fresh one, one T3 sent without a thread status, another app: untouched', () => {
    expect(t3Settled([done], { alive: false }, now)).toEqual([]);
    expect(t3Settled([n({ app: 'T3 Code', title: 'X', status: 'Thread completed', time: now - 30000 })], t3([]), now)).toEqual([]);
    expect(t3Settled([n({ app: 'T3 Code', title: 'Update ready', status: '' , time: now - 60 * min })], t3([]), now)).toEqual([]);
    expect(t3Settled([n({ app: 'Mail', status: 'x', time: now - 60 * min })], t3([]), now)).toEqual([]);
  });
  test('more unopened threads than T3 lists: only ones newer than the oldest listed are judged', () => {
    const listed = [{ title: 'Newest', status: 'completed', at: '2026-11-21T11:00:00Z' }];
    const old = n({ app: 'T3 Code', title: 'Old one', status: 'Thread completed', time: Date.parse('2026-11-21T08:00:00Z') });
    const newer = n({ app: 'T3 Code', title: 'Opened one', status: 'Thread completed', time: Date.parse('2026-11-21T11:30:00Z') });
    expect(t3Settled([old, newer], t3(listed, 30), now)).toEqual([newer]);
  });
});

describe('what expires on its own', () => {
  const lastSeen = now - 5 * min;
  test('a sudo prompt: gone after ten minutes, seen or not', () => {
    expect(expired([n({ app: 'Sudo', body: 'sudo is asking for your password', time: now - 11 * min })], now, lastSeen, 24).length).toBe(1);
    expect(expired([n({ app: 'Sudo', body: 'sudo is asking for your password', time: now - 2 * min })], now, lastSeen, 24).length).toBe(0);
  });
  test('low urgency: an hour after it was seen; unseen ones wait for you', () => {
    expect(expired([n({ urgency: 0, time: now - 61 * min })], now, lastSeen, 24).length).toBe(1);
    expect(expired([n({ urgency: 0, time: now - 30 * min })], now, lastSeen, 24).length).toBe(0);
    expect(expired([n({ urgency: 0, time: now - 2 * min })], now, now - 10 * min, 24).length).toBe(0);
  });
  test('the rest: Keep seen notifications (hours); 0 keeps them', () => {
    expect(expired([n({ time: now - 25 * 60 * min })], now, lastSeen, 24).length).toBe(1);
    expect(expired([n({ time: now - 23 * 60 * min })], now, lastSeen, 24).length).toBe(0);
    expect(expired([n({ time: now - 25 * 60 * min })], now, lastSeen, 0).length).toBe(0);
  });
  test('a toast on screen or one leaving is never swept', () => {
    expect(expired([n({ app: 'Sudo', body: 'sudo is asking for your password', time: now - 60 * min, popup: true })], now, lastSeen, 24)).toEqual([]);
  });
});

test('repeats already in the history collapse to the newest', () => {
  const rows = [1, 2, 3, 4].map(k => n({ app: 'voxtype', body: 'NVIDIA driver updated', time: now - k * min }));
  const other = n({ app: 'voxtype', body: 'moved files', time: now });
  expect(olderTwins([rows[2], other, rows[0], rows[3], rows[1]])).toEqual([rows[1], rows[2], rows[3]]);
});
