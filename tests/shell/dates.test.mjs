// shell/config/dates.mjs: the date and time shapes cut from a locale's own
// formats. The format strings are Qt 6.12's (Locale.dateFormat(LongFormat),
// timeFormat(ShortFormat)); tests/shell/test_dates_locale.py runs the same
// module in Qt's engine under real locales.
import { expect, test } from 'bun:test';
import { tokenize, build, without, dateShapes, timeShapes, weekOrder, leadDays, dayOffset, relativeDay, resolve, formatter } from '../../shell/config/dates.mjs';

const QT = {
  en_US: ['dddd, MMMM d, yyyy', 'h:mm Ap'],
  de_DE: ['dddd, d. MMMM yyyy', 'HH:mm'],
  en_GB: ['dddd, d MMMM yyyy', 'HH:mm'],
  ja_JP: ['yyyy年M月d日dddd', 'H:mm'],
  es_ES: ["dddd, d 'de' MMMM 'de' yyyy", 'H:mm'],
  ru_RU: ["dddd, d MMMM yyyy 'г'.", 'HH:mm'],
  ko_KR: ['yyyy년 MMMM d일 dddd', 'Ap h:mm'],
  hu_HU: ['yyyy. MMMM d., dddd', 'H:mm'],
  tr_TR: ['d MMMM yyyy dddd', 'HH:mm'],
  fi_FI: ['dddd d. MMMM yyyy', 'H.mm'],
  ar_EG: ['dddd، d MMMM yyyy', 'h:mm Ap'],
};

test('a format splits into fields and literal text, and builds back', () => {
  expect(tokenize("dddd, d 'de' MMMM")).toEqual([
    { field: 'dddd', text: '' }, { field: '', text: ', ' }, { field: 'd', text: '' },
    { field: '', text: ' de ' }, { field: 'MMMM', text: '' }]);
  expect(tokenize('h:mm Ap').map(t => t.field || t.text)).toEqual(['h', ':', 'mm', ' ', 'Ap']);
  expect(tokenize("h 'o''clock'").map(t => t.field || t.text)).toEqual(['h', " o'clock"]);
  expect(build(tokenize("d 'de' MMMM"))).toBe("d' de 'MMMM");
  expect(build(tokenize('yyyy年M月'))).toBe('yyyy年M月');
});

test('the long date drops the year, its suffix and the separator before it', () => {
  const long = Object.fromEntries(Object.entries(QT).map(([k, [d]]) => [k, dateShapes(d).long]));
  expect(long).toEqual({
    en_US: 'dddd, MMMM d', de_DE: 'dddd, d. MMMM', en_GB: 'dddd, d MMMM', ja_JP: 'M月d日dddd',
    es_ES: "dddd, d' de 'MMMM", ru_RU: 'dddd, d MMMM', ko_KR: 'MMMM d일 dddd', hu_HU: 'MMMM d., dddd',
    tr_TR: 'd MMMM dddd', fi_FI: 'dddd d. MMMM', ar_EG: 'dddd، d MMMM',
  });
});

test('the other shapes keep the locale\'s order and suffixes', () => {
  expect(dateShapes(QT.en_US[0])).toEqual({ long: 'dddd, MMMM d', short: 'ddd, MMM d', dayMonth: 'MMM d', dayMonthYear: 'MMM d, yyyy', monthYear: 'MMMM yyyy' });
  expect(dateShapes(QT.de_DE[0])).toEqual({ long: 'dddd, d. MMMM', short: 'ddd, d. MMM', dayMonth: 'd. MMM', dayMonthYear: 'd. MMM yyyy', monthYear: 'MMMM yyyy' });
  expect(dateShapes(QT.ja_JP[0])).toEqual({ long: 'M月d日dddd', short: 'M月d日ddd', dayMonth: 'M月d日', dayMonthYear: 'yyyy年M月d日', monthYear: 'yyyy年M月' });
  expect(dateShapes(QT.es_ES[0]).monthYear).toBe("MMMM' de 'yyyy");
  expect(dateShapes(QT.hu_HU[0]).monthYear).toBe('yyyy. MMMM');
  expect(dateShapes(QT.hu_HU[0]).dayMonth).toBe('MMM d.');
  expect(dateShapes(QT.ko_KR[0]).monthYear).toBe('yyyy년 MMMM');
  expect(dateShapes(QT.ru_RU[0]).dayMonthYear).toBe('d MMM yyyy г.');
});

test('a format that is not a full date falls back to English order', () => {
  expect(dateShapes('').long).toBe('dddd, MMMM d');
  expect(dateShapes('d/M/yy').short).toBe('ddd, MMM d');
});

test('the hour cycle is the setting; the marker and separator are the locale\'s', () => {
  expect(timeShapes(QT.en_US[1], true)).toEqual({ time: 'HH:mm', clock: 'HH:mm', clockSeconds: 'HH:mm:ss' });
  expect(timeShapes(QT.en_US[1], false)).toEqual({ time: 'h:mm Ap', clock: 'h:mm', clockSeconds: 'h:mm:ss' });
  expect(timeShapes(QT.ko_KR[1], false).time).toBe('Ap h:mm');
  expect(timeShapes(QT.ko_KR[1], true).time).toBe('HH:mm');
  expect(timeShapes(QT.de_DE[1], false).time).toBe('h:mm Ap');
  expect(timeShapes(QT.ja_JP[1], true).time).toBe('H:mm');        // the locale's own 24-hour digits
  expect(timeShapes(QT.fi_FI[1], true)).toEqual({ time: 'H.mm', clock: 'H.mm', clockSeconds: 'H.mm.ss' });
  expect(timeShapes('', true).time).toBe('HH:mm');
});

test('a 12-hour clock without its marker writes the hour itself', () => {
  const at = new Date(2026, 10, 17, 21, 5);
  expect(resolve('h:mm', at, false, null)).toBe('9:mm');
  expect(resolve('hh:mm', new Date(2026, 10, 17, 0, 5), false, null)).toBe('12:mm');
  expect(resolve('hh:mm', new Date(2026, 10, 17, 8, 5), false, null)).toBe('08:mm');
  expect(resolve('h:mm Ap', at, false, null)).toBe('h:mm Ap');     // Qt does it right with a marker
  expect(resolve('HH:mm', at, true, null)).toBe('HH:mm');
});

test('a month without a day is named on its own', () => {
  const names = ['январь', 'февраль', 'март', 'апрель', 'май', 'июнь', 'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь'];
  const at = new Date(2026, 10, 17);
  expect(resolve('MMMM yyyy', at, true, m => names[m])).toBe('ноябрь yyyy');
  expect(resolve('MMMM yyyy', new Date(2026, 4, 1), true, () => 'May')).toBe("'May' yyyy");   // quoted: M, a, y are fields
  expect(resolve('d MMMM', at, true, m => names[m])).toBe('d MMMM');
});

test('the week starts on the locale\'s first day', () => {
  expect(weekOrder(0)).toEqual([0, 1, 2, 3, 4, 5, 6]);
  expect(weekOrder(1)).toEqual([1, 2, 3, 4, 5, 6, 0]);
  expect(weekOrder(6)).toEqual([6, 0, 1, 2, 3, 4, 5]);
  expect(weekOrder(8)).toEqual([1, 2, 3, 4, 5, 6, 0]);
  // November 2026 starts on a Sunday.
  const first = new Date(2026, 10, 1).getDay();
  expect([leadDays(first, 0), leadDays(first, 1), leadDays(first, 6)]).toEqual([0, 6, 1]);
  expect(leadDays(1, 1)).toBe(0);
});

test('relative days count local midnights, across daylight saving', () => {
  const old = process.env.TZ; process.env.TZ = 'Europe/Berlin';
  try {
    const now = new Date(2026, 2, 30, 0, 30);          // the day after the clocks went forward
    expect(dayOffset(new Date(2026, 2, 29, 23, 59), now)).toBe(-1);
    expect(relativeDay(new Date(2026, 2, 29, 1, 0), now)).toBe('Yesterday');
    expect(relativeDay(new Date(2026, 2, 30, 23, 0), now)).toBe('Today');
    expect(relativeDay(new Date(2026, 2, 31, 0, 0), now)).toBe('Tomorrow');
    expect(relativeDay(new Date(2026, 2, 28), now)).toBe('');
    expect(dayOffset(new Date(2027, 0, 1), new Date(2026, 11, 31, 23))).toBe(1);
  } finally { if (old === undefined) delete process.env.TZ; else process.env.TZ = old; }
});

test('the formatter hands Qt one pattern per shape', () => {
  const seen = [];
  const loc = { dateFormat: () => QT.de_DE[0], timeFormat: () => QT.de_DE[1], firstDayOfWeek: 1, dayName: (i) => 'So Mo Di Mi Do Fr Sa'.split(' ')[i] };
  const f = formatter(loc, true, (d, p) => { seen.push(p); return p; }, { long: 0, short: 1, narrow: 2 });
  const at = new Date(2026, 10, 17, 21, 5);
  expect(f.long(at)).toBe('dddd, d. MMMM');
  expect(f.short(at)).toBe('ddd, d. MMM');
  expect(f.clock(at, true)).toBe('HH:mm:ss');
  expect(f.weekdayTime(at)).toBe('ddd HH:mm');
  expect(f.day(at, at)).toBe('Today');
  expect(f.stamp(at, at)).toBe('HH:mm');
  expect(f.stamp(new Date(2026, 0, 2), at)).toBe('d. MMM');
  expect(f.stamp(new Date(2025, 0, 2), at)).toBe('d. MMM yyyy');
  expect(f.weekdayNames()).toEqual(['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']);
  expect(f.lead(new Date(2026, 10, 1))).toBe(6);
  expect(f.monthYearParts(at).map(p => [p.text, p.year])).toEqual([['MMMM', false], ['yyyy', true]]);
  const ja = formatter({ dateFormat: () => QT.ja_JP[0], timeFormat: () => QT.ja_JP[1], firstDayOfWeek: 0, dayName: () => '' }, true, (d, p) => p, { long: 0, short: 1, narrow: 2 });
  expect(ja.monthYearParts(at).map(p => [p.text, p.year])).toEqual([['yyyy年', true], ['M月', false]]);
});
