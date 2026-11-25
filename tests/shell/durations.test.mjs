import { test, expect } from 'bun:test';
import { readFileSync } from 'node:fs';

const theme = readFileSync(new URL('../../shell/config/Theme.qml', import.meta.url), 'utf8');
const value = name => {
  const m = theme.match(new RegExp(`readonly property int ${name}: (\\w+)`));
  if (!m) throw new Error(name);
  return /^\d+$/.test(m[1]) ? Number(m[1]) : value(m[1]);
};
const shared = ['hoverMs', 'pressMs', 'colorMs', 'quickMs', 'microMs', 'glideMs', 'exitMs', 'enterMs', 'reflowMs',
  'swipeOutMs', 'unmountMs', 'settleMs', 'hudInMs', 'hudOutMs', 'menuInMs', 'menuOutMs', 'artMs', 'stackMs', 'breatheMs', 'swingMs', 'kickMs'];

test('the shared roles are on the scale, not their own numbers', () => {
  for (const name of shared) expect(theme).toMatch(new RegExp(`readonly property int ${name}: dur[A-Z]\\w*`));
});
test('leaving is quicker than arriving', () => {
  expect(value('exitMs')).toBeLessThan(value('enterMs'));
  expect(value('menuOutMs')).toBeLessThan(value('menuInMs'));
  expect(value('hudOutMs')).toBeLessThan(value('hudInMs'));
});
