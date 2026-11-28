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

// Screens off while agents worked (2026-11-21): turning them off disconnects
// the external monitor here and Hyprland moved its workspaces onto the laptop
// and back. While work runs on power the screens stay on (dim and lock still
// happen), whatever Keep awake says; they go off once it ends if you're away.
test('the screens stay on while work runs on power, and go off after', () => {
  const idle = readFileSync(new URL('../../shell/services/Idle.qml', import.meta.url), 'utf8');
  const caf = readFileSync(new URL('../../shell/services/Caffeine.qml', import.meta.url), 'utf8');
  expect(idle).toMatch(/screensHeld: Settings\.idleScreensWhileWork && Caffeine\.workNow\.length > 0/);
  expect(idle).toMatch(/if \(isIdle && root\.screensHeld\) return;/);
  expect(idle).toMatch(/onScreensHeldChanged: if \(!screensHeld && offMonitor\.enabled && offMonitor\.isIdle && !Saver\.screensOff\) screens\(true\)/);
  // workNow ignores Keep awake; Keep awake's "work" mode is still only that mode's.
  expect(caf).toMatch(/readonly property var workNow: \{\s*if \(UPower\.onBattery\) return \[\];/);
  expect(caf).toMatch(/readonly property var reasons: Settings\.caffeineMode === "work" \? workNow : \[\]/);
  const schema = JSON.parse(readFileSync(new URL('../../shell/config/settings-schema.json', import.meta.url), 'utf8'));
  const list = Array.isArray(schema) ? schema : schema.settings;
  expect(list.find(s => s.key === 'idleScreensWhileWork').default).toBe(true);
});

// Closing the notification centre crashed the shell (2026-11-20 21:47,
// 11-21 09:36): ScrollFade took the list's layer down inside the change that
// tore the view down, and Qt then used the layer's deleted source. The layer
// is decided a moment later now (bin/kuwai-ui-test --case center-keys fails
// on any crash, teardown included). And the restart after a crash came up on
// Quickshell's default config, an old prototype: the path rides along in the
// environment so a restart is kuwai again.
test('ScrollFade never switches a layer inside the change that asked for it', () => {
  const src = readFileSync(new URL('../../shell/components/ScrollFade.qml', import.meta.url), 'utf8');
  expect(src).toMatch(/onScrollsChanged:\s*settle\.restart\(\)/);
  expect(src).not.toMatch(/onScrollsChanged:\s*apply\(\)/);
  expect(src).toMatch(/liveLayer/);
  expect(src).toMatch(/head > 0\.01 \|\| foot > 0\.01/);
});

test('a restarted shell is kuwai: its path is in its environment', () => {
  const src = readFileSync(new URL('../../bin/kuwai-shell', import.meta.url), 'utf8');
  expect(src).toMatch(/envs\+=\("QS_CONFIG_PATH=\$SHELL_DIR"\)/);
  const at = src.indexOf('QS_CONFIG_PATH=');
  expect(at).toBeLessThan(src.indexOf('qs -p "$SHELL_DIR" -d'));
});
