import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { order, holdMs, fileUrl, decodeSide, after } from '../../shell/modules/screensaver/saverPhotos.mjs';

const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

test('a shuffle shows every picture once, the same way for the same seed, differently for another', () => {
  for (const n of [0, 1, 2, 7, 40]) {
    const a = order(n, 12345);
    expect(a.length).toBe(n);
    expect([...a].sort((x, y) => x - y)).toEqual([...Array(n).keys()]);
    expect(order(n, 12345)).toEqual(a);
  }
  expect(order(30, 1)).not.toEqual(order(30, 2));
  expect(order(-3, 1)).toEqual([]);
  expect(order(NaN, 1)).toEqual([]);
  expect(order(5, undefined).length).toBe(5);
});

test('each photo stays its minutes, kept to something sensible', () => {
  expect(holdMs(5)).toBe(300000);
  expect(holdMs(1)).toBe(60000);
  expect(holdMs(0)).toBe(300000);
  expect(holdMs(undefined)).toBe(300000);
  expect(holdMs(9999)).toBe(7200000);
});

test('a name with a hash or a question mark is still that file', () => {
  expect(fileUrl('/home/a/Pictures/a b.jpg')).toBe('file:///home/a/Pictures/a%20b.jpg');
  expect(fileUrl('/p/c#1.png')).toBe('file:///p/c%231.png');
  expect(fileUrl('/p/what?.png')).toBe('file:///p/what%3F.png');
  expect(fileUrl('')).toBe('');
});

test('pictures are decoded at the screen, never past the cap', () => {
  expect(decodeSide(1920, 1080, 2560)).toBe(1920);
  expect(decodeSide(1080, 1920, 2560)).toBe(1920);
  expect(decodeSide(3840, 2160, 2560)).toBe(2560);
  expect(decodeSide(0, 0, 2560)).toBe(1);
});

test('the next picture skips what would not load, and stops when nothing else is left', () => {
  expect(after(0, 5, {})).toBe(1);
  expect(after(4, 5, {})).toBe(0);
  expect(after(0, 5, { 1: true, 2: true })).toBe(3);
  expect(after(0, 3, { 1: true, 2: true })).toBe(-1);
  expect(after(0, 1, {})).toBe(-1);
  expect(after(0, 0, {})).toBe(-1);
});

test('photos cost one picture on screen and one waiting, decoded off the main thread and not cached', () => {
  const q = read('shell/modules/screensaver/PhotoShuffle.qml');
  expect((q.match(/\bImage \{/g) || []).length).toBe(2);
  expect((q.match(/asynchronous: true/g) || []).length).toBe(2);
  expect((q.match(/cache: false/g) || []).length).toBe(2);
  expect(q).toMatch(/running: shuffle\.running && shuffle\.count > 1/);
  expect(q).toMatch(/Photos\.after\(at, count, bad\)/);
  const saver = read('shell/modules/screensaver/Screensaver.qml');
  expect(saver).toMatch(/active: stage\.photosHere && root\.photosListed && !root\.longDark/);
  expect(saver).toMatch(/running: root\.showing && root\.style === "photos"/);
  expect(saver).toMatch(/kuwai-saver-photos", Settings\.screensaverFolder/);
});

test('the photo settings keep today\'s look: still is the default, five minutes, the theme\'s own wallpapers', () => {
  const schema = JSON.parse(read('shell/config/settings-schema.json'));
  const key = k => schema.settings.find(e => e.key === k);
  expect(key('screensaverStyle').default).toBe('still');
  expect(key('screensaverStyle').enum).toContain('photos');
  expect(key('screensaverPhotoMins')).toMatchObject({ default: 5, min: 1, type: 'integer', section: 'saver' });
  expect(key('screensaverFolder')).toMatchObject({ default: '', type: 'string', section: 'saver' });
});
