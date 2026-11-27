import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { functions } from '../helpers/qml.mjs';

const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const hex = s => String(s).toLowerCase();
const Qt = {
  color: s => typeof s === 'string' ? { hex: hex(s), r: 0.1, g: 0.2, b: 0.3, hslHue: 0.6, hslSaturation: 0.8, hslLightness: 0.7 } : s,
  hsla: (h, s, l, a) => ({ hex: `hsla(${h},${s},${l},${a})` }),
  rgba: (r, g, b, a) => ({ hex: `rgba(${r},${g},${b},${a})` }),
  colorEqual: (a, b) => JSON.stringify(Qt.color(a)) === JSON.stringify(Qt.color(b)),
};

function theme() {
  const sets = {};
  const file = () => ({ loaded: false, body: '', text() { return this.body; } });
  const scope = { Qt, JSON, colorMode: 0, themeName: '', wallTopLuma: 0.1, palette: [],
    kuwaiPalette: file(), themeDcol: file(), themeKitty: file(), wallDcol: file(),
    recolorSettle: { restarts: 0, restart() { this.restarts++; } } };
  for (const k of ['accent', 'accentSoft', 'themeBg', 'themeFg', 'wallInk']) {
    let v = { hex: 'start-' + k };
    sets[k] = 0;
    Object.defineProperty(scope, k, { get: () => v, set: x => { v = x; sets[k]++; }, enumerable: true });
  }
  functions('shell/config/Theme.qml', ['vivid', 'parseDcol', 'fromDcol', 'fromKitty', 'fromKuwaiLook', 'colours', 'commit', 'recolor'], scope);
  scope.fire = () => scope.commit(scope.colours());
  return { t: scope, sets };
}
const dcol = (accent, bg) => `dcol_pry1="${bg}"\ndcol_1xa7="${accent}"\ndcol_txt1="FFFFFF"\n`;

test('a burst of file changes is one recolour: every load only restarts the settle timer', () => {
  const { t, sets } = theme();
  for (let i = 0; i < 5; i++) t.recolor();
  expect(t.recolorSettle.restarts).toBe(5);
  expect(sets.accent).toBe(0);
});

test('HyDE switching theme lands once, on the theme, never on the wallpaper colours on the way', () => {
  const { t, sets } = theme();
  t.wallDcol.loaded = true; t.wallDcol.body = dcol('AA0000', '110000');
  t.themeName = 'Pixel Dusk';
  t.recolor();
  t.themeDcol.loaded = true; t.themeDcol.body = dcol('00AA00', '001100');
  t.recolor();
  expect(t.fire()).toBeGreaterThan(0);
  expect(sets.accent).toBe(1);
  expect(sets.themeBg).toBe(1);
  expect(t.themeBg.hex).toBe('#001100');
  expect(t.palette).toEqual(['#001100', '#00AA00']);
});

test('the same colours again change nothing', () => {
  const { t, sets } = theme();
  t.wallDcol.loaded = true; t.wallDcol.body = dcol('AA0000', '110000');
  t.colorMode = 1;
  t.fire();
  const after = { ...sets };
  expect(t.fire()).toBe(0);
  expect(sets).toEqual(after);
});

test("kuwai look's palette wins and brings its mode, name and wall ink in the same commit", () => {
  const { t, sets } = theme();
  t.wallDcol.loaded = true; t.wallDcol.body = dcol('AA0000', '110000');
  t.kuwaiPalette.loaded = true;
  t.kuwaiPalette.body = JSON.stringify({ schema: 1, mode: 'theme', role: { accent: '#3366ff', bg: '#101014' }, swatches: ['#101014', '#3366ff'],
    source: { name: 'Kuwai Night' }, wall: { topLuma: 0.4, ink: '#000000' } });
  t.colorMode = 2;
  t.fire();
  expect(t.accent.hex).toBe('#3366ff');
  expect(t.themeName).toBe('Kuwai Night');
  expect(t.colorMode).toBe(0);
  expect(t.wallTopLuma).toBe(0.4);
  expect(sets.accent).toBe(1);
  expect(sets.wallInk).toBe(1);
});

test('only the always-visible fills blend; the accent itself is one commit', () => {
  const qml = read('shell/config/Theme.qml');
  expect(qml).not.toMatch(/Behavior on accent\s*\{/);
  expect(qml).toMatch(/property color accentLive: accent\n\s*Behavior on accentLive \{ ColorAnimation/);
  expect(qml).toMatch(/Timer \{ interval: root\.recolorMs; onTriggered: root\.commit\(root\.colours\(\)\) \}/);
  for (const m of qml.matchAll(/onLoaded: \{[^}]*\}/g)) expect(m[0]).not.toMatch(/from(Dcol|Kitty|KuwaiLook)\(/);
  const capsules = read('shell/modules/island/Capsules.qml');
  expect(capsules).not.toMatch(/Theme\.accent\b(?!Live)/);
  expect(capsules).toMatch(/Theme\.accentLive/);
});
