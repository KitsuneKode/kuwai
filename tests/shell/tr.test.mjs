// shell/config/tr.mjs: the catalogue lookup behind Tr.qml, and the real
// catalogues under shell/i18n/. tests/shell/test_tr_quickshell.py runs the
// singleton itself in an offscreen Quickshell under real locales.
import { expect, test } from 'bun:test';
import { readFileSync, readdirSync } from 'node:fs';
import { t, n, plural, categories, fill, placeholders, candidates, pick, parse, pseudo } from '../../shell/config/tr.mjs';
import { relativeDay, formatter } from '../../shell/config/dates.mjs';

const dir = new URL('../../shell/i18n/', import.meta.url);
const de = parse(readFileSync(new URL('de.json', dir), 'utf8'));
const available = parse(readFileSync(new URL('languages.json', dir), 'utf8')).languages;

test('English by default: no catalogue, the key is the text', () => {
  expect(pick(candidates(['en-Latn-US', 'en-US', 'en-Latn', 'en']), available)).toBe('');
  expect(t({}, 'Shut Down')).toBe('Shut Down');
  expect(t({}, 'Hold to {action}', { action: 'restart' })).toBe('Hold to restart');
  expect(n({}, '', 1, '{n} update', '{n} updates')).toBe('1 update');
  expect(n({}, '', 3, '{n} update', '{n} updates')).toBe('3 updates');
});

test('German under a German locale', () => {
  const lang = pick(candidates(['de-Latn-DE', 'de-DE', 'de-Latn', 'de']), available);
  expect(lang).toBe('de');
  expect(t(de, 'Shut Down')).toBe('Herunterfahren');
  expect(t(de, 'Today')).toBe('Heute');
  expect(t(de, 'up {time}', { time: '1 T. 2 Std.' })).toBe('seit 1 T. 2 Std. an');
});

test('an unknown key, an empty or a non-string translation fall back to English', () => {
  expect(t(de, 'A string nobody translated')).toBe('A string nobody translated');
  expect(t({ Lock: '' }, 'Lock')).toBe('Lock');
  expect(t({ Lock: { one: 'x' } }, 'Lock')).toBe('Lock');
  expect(t(Object.create(null), 'toString')).toBe('toString');
  expect(t({}, 'constructor')).toBe('constructor');
  expect(n(de, 'de', 2, '{n} new thing', '{n} new things')).toBe('2 new things');
});

test('plural forms: the category for the count, in the language', () => {
  const cat = {
    '{n} update': { one: '{n} Aktualisierung', other: '{n} Aktualisierungen' },
    '{n} file in {folder}': { one: 'eine Datei in {folder}', other: '{n} Dateien in {folder}' },
  };
  expect(n(cat, 'de', 1, '{n} update', '{n} updates')).toBe('1 Aktualisierung');
  expect(n(cat, 'de', 0, '{n} update', '{n} updates')).toBe('0 Aktualisierungen');
  expect(n(cat, 'de', 21, '{n} update', '{n} updates')).toBe('21 Aktualisierungen');
  expect(n(cat, 'de', 1, '{n} file in {folder}', '{n} files in {folder}', { folder: 'Bilder' })).toBe('eine Datei in Bilder');
  expect(n(cat, 'de', 4, '{n} file in {folder}', '{n} files in {folder}', { folder: 'Bilder' })).toBe('4 Dateien in Bilder');
  // Russian: one / few / many by the last digits.
  const ru = { '{n} file': { one: '{n} файл', few: '{n} файла', many: '{n} файлов', other: '{n} файла' } };
  expect([1, 2, 5, 11, 21, 22, 25, 112].map(c => n(ru, 'ru', c, '{n} file', '{n} files')))
    .toEqual(['1 файл', '2 файла', '5 файлов', '11 файлов', '21 файл', '22 файла', '25 файлов', '112 файлов']);
  expect([0, 1, 2].map(c => plural('fr', c))).toEqual(['one', 'one', 'other']);
  expect([0, 1, 2, 3, 11, 100].map(c => plural('ar', c))).toEqual(['zero', 'one', 'two', 'few', 'many', 'other']);
  expect([1, 2, 5, 22, 12].map(c => plural('pl', c))).toEqual(['one', 'few', 'many', 'few', 'many']);
  expect(plural('ja', 1)).toBe('other');
  expect(categories('ja')).toEqual(['other']);
  // A language with one form may give a plain string.
  expect(n({ '{n} file': '{n}個のファイル' }, 'ja', 3, '{n} file', '{n} files')).toBe('3個のファイル');
  // A missing category falls to other.
  expect(n({ '{n} file': { other: '{n} plików' } }, 'pl', 1, '{n} file', '{n} files')).toBe('1 plików');
});

test('placeholders fill as plain text and are never looked up', () => {
  expect(fill('{who} sent {n}', { who: 'Shut Down', n: 2 })).toBe('Shut Down sent 2');
  expect(t(de, 'up {time}', { time: 'Today' })).toBe('seit Today an');
  expect(fill('{missing} and {}', { n: 1 })).toBe('{missing} and {}');
  expect(fill('a { b', { b: 1 })).toBe('a { b');
  expect(placeholders('{n} of {total}, {n}')).toEqual(['n', 'total']);
});

test('the language list: LANGUAGE order, script tags dropped, English stops it', () => {
  expect(candidates(['de-Latn-DE', 'de-DE', 'de-Latn', 'de', 'fr-Latn-FR', 'fr-FR', 'fr-Latn', 'fr'])).toEqual(['de_DE', 'de', 'fr_FR', 'fr']);
  expect(candidates(['fr-FR', 'de-DE'])).toEqual(['fr_FR', 'fr', 'de_DE', 'de']);
  expect(pick(candidates(['fr-FR', 'de-DE']), available)).toBe('de');
  expect(candidates(['en-GB', 'de-DE'])).toEqual([]);
  expect(candidates(['pt-BR'])).toEqual(['pt_BR', 'pt']);
  expect(candidates(['zh-Hant-TW'])).toEqual(['zh_TW', 'zh']);
  expect(candidates([])).toEqual([]);
});

test('a broken catalogue reads as none (English), never throws', () => {
  expect(parse('{ not json')).toEqual({});
  expect(parse('[1, 2]')).toEqual({});
  expect(parse('')).toEqual({});
  expect(parse('null')).toEqual({});
});

test('pseudo-localisation: at least 40 % longer, placeholders intact', () => {
  for (const s of ['Lock', 'Shut Down', 'Hold to restart into the firmware setup']) {
    const p = pseudo(s);
    expect(p.length).toBeGreaterThanOrEqual(Math.ceil(s.length * 1.4));
  }
  expect(fill(pseudo('{n} updates'), { n: 3 })).toContain('3');
});

test('the shipped catalogues: every key a string or every plural category of its language', () => {
  for (const f of readdirSync(dir).filter(f => f.endsWith('.json') && f !== 'languages.json')) {
    const lang = f.slice(0, -5);
    expect(available).toContain(lang);
    const cat = parse(readFileSync(new URL(f, dir), 'utf8'));
    expect(Object.keys(cat).length).toBeGreaterThan(0);
    for (const [k, v] of Object.entries(cat)) {
      if (typeof v === 'string') { expect(v.length).toBeGreaterThan(0); continue; }
      expect(Object.keys(v).sort()).toEqual(categories(lang).slice().sort());
      expect(k).toContain('{n}');
    }
  }
});

test('the relative days take the given words; English without them', () => {
  const now = new Date(2026, 10, 17, 12);
  const y = new Date(2026, 10, 16, 23);
  expect(relativeDay(now, now)).toBe('Today');
  expect(relativeDay(y, now)).toBe('Yesterday');
  const words = { today: t(de, 'Today'), yesterday: t(de, 'Yesterday'), tomorrow: t(de, 'Tomorrow') };
  expect(relativeDay(y, now, words)).toBe('Gestern');
  expect(relativeDay(new Date(2026, 10, 18), now, words)).toBe('Morgen');
  expect(relativeDay(new Date(2026, 10, 20), now, words)).toBe('');
  const loc = { dateFormat: () => 'dddd, d. MMMM yyyy', timeFormat: () => 'HH:mm', firstDayOfWeek: 1, dayName: () => '' };
  const f = formatter(loc, true, (_d, p) => p, { long: 0, short: 1, narrow: 2 }, words);
  expect(f.day(now, now)).toBe('Heute');
  expect(formatter(loc, true, (_d, p) => p, { long: 0, short: 1, narrow: 2 }).day(now, now)).toBe('Today');
});
