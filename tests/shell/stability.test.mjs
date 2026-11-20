// The lock and screens coming back (2026-11-21). Waking with the session
// locked, the external monitor returns as a new output; the shell used to
// restart itself to cover it, and the process that holds the lock going away
// is what showed Hyprland's "lock screen died" screen at every wake. Now it
// restarts only when a screen is really left without a lock surface.
import { expect, test } from 'bun:test';
import { functions } from '../helpers/qml.mjs';

function lock({ screens, surfaces, locked = true, secure = true }) {
  const started = [];
  const scope = {
    locked, secure,
    lockSurfaces: surfaces.map(name => ({ screen: name ? { name } : null })),
    Quickshell: { screens: screens.map(name => ({ name })), execDetached(cmd) { started.push(cmd); } },
    Paths: { bin: '/bin' },
    console: { info() {}, warn() {} },
  };
  const f = functions('shell/modules/lock/Lock.qml', ['uncovered', 'resurface'], scope);
  f.resurface();
  return { started, missing: f.uncovered() };
}

test('a monitor back from power-off with its lock surface: no restart', () => {
  const r = lock({ screens: ['eDP-1', 'DP-3'], surfaces: ['eDP-1', 'DP-3'] });
  expect(r.missing).toEqual([]);
  expect(r.started).toEqual([]);
});

test('a screen left without a lock surface: the shell restarts to cover it', () => {
  const r = lock({ screens: ['eDP-1', 'DP-3'], surfaces: ['eDP-1', null] });
  expect(r.missing).toEqual(['DP-3']);
  expect(r.started).toEqual([['/bin/kuwai-shell']]);
});

test('not locked, or the lock not confirmed yet: nothing happens', () => {
  expect(lock({ screens: ['DP-3'], surfaces: [], locked: false }).started).toEqual([]);
  expect(lock({ screens: ['DP-3'], surfaces: [], secure: false }).started).toEqual([]);
});

// The center crashed the shell as it opened (2026-11-20 21:47): a segfault in
// Qt's icon loader (QIconLoader::findIconHelper) inside a binding that asked
// for a theme icon. Theme icon names are asked once, through NotifAdapters'
// cache; nothing else calls Quickshell.iconPath(…, true) by itself.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
test('theme icons are looked up through the one cache', () => {
  const root = new URL('../../shell/', import.meta.url).pathname;
  const hits = [];
  const walk = dir => { for (const n of readdirSync(dir)) { const p = join(dir, n); if (statSync(p).isDirectory()) walk(p); else if (p.endsWith('.qml')) {
    const s = readFileSync(p, 'utf8').split('\n');
    s.forEach((l, i) => { if (/Quickshell\.iconPath\([^)]*,\s*true\)/.test(l) && !/^\s*\/\//.test(l)) hits.push(p.slice(root.length) + ':' + (i + 1)); });
  } } };
  walk(root);
  expect(hits).toEqual(['services/NotifAdapters.qml:' + (readFileSync(root + 'services/NotifAdapters.qml', 'utf8').split('\n').findIndex(l => /Quickshell\.iconPath\(icon, true\)/.test(l)) + 1)]);
});
