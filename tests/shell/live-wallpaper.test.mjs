import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { functions } from '../helpers/qml.mjs';

const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

function saver() {
  const scope = {
    screensOff: false,
    outputOff: {},
    dpmsProbe: { running: false, again: false },
  };
  return functions('shell/services/Saver.qml', ['isOutputOff', 'applyMonitors', 'handleHyprEvent', 'probeDpms'], scope);
}

test('compositor dpmsStatus drives per-output and all-screens off state', () => {
  const s = saver();
  expect(s.applyMonitors(JSON.stringify([
    { name: 'eDP-1', dpmsStatus: true, disabled: false },
    { name: 'DP-3', dpmsStatus: false, disabled: false },
  ]))).toBe(true);
  expect(s.screensOff).toBe(false);
  expect(s.isOutputOff('eDP-1')).toBe(false);
  expect(s.isOutputOff('DP-3')).toBe(true);

  expect(s.applyMonitors(JSON.stringify([
    { name: 'eDP-1', dpmsStatus: false, disabled: false },
    { name: 'DP-3', dpmsStatus: false, disabled: false },
  ]))).toBe(true);
  expect(s.screensOff).toBe(true);
  expect(s.isOutputOff('eDP-1')).toBe(true);
  expect(s.isOutputOff('DP-3')).toBe(true);

  expect(s.applyMonitors(JSON.stringify([
    { name: 'eDP-1', dpmsStatus: true, disabled: false },
    { name: 'DP-3', dpmsStatus: true, disabled: false },
  ]))).toBe(true);
  expect(s.screensOff).toBe(false);
  expect(s.isOutputOff('DP-3')).toBe(false);
});

test('Hyprland dpms and monitor events update output state and trigger compositor probe', () => {
  const s = saver();
  s.handleHyprEvent('dpms', 'DP-3,0');
  expect(s.isOutputOff('DP-3')).toBe(true);
  expect(s.dpmsProbe.running).toBe(true);
  s.handleHyprEvent('monitoraddedv2', '2,DP-3,desc');
  expect(s.dpmsProbe.again).toBe(true);
  s.dpmsProbe.running = false;
  s.dpmsProbe.again = false;
  s.handleHyprEvent('dpms', 'DP-3,1');
  expect(s.isOutputOff('DP-3')).toBe(false);
  expect(s.dpmsProbe.running).toBe(true);
});

test('Idle dispatches DPMS and queries the compositor instead of guessing Saver.screensOff', () => {
  const idle = read('shell/services/Idle.qml');
  expect(idle).not.toMatch(/Saver\.screensOff\s*=\s*off/);
  expect(idle).toMatch(/Saver\.probeDpms\(\)/);
});

function liveSlot(overrides = {}) {
  const qml = read('shell/modules/wallpaper/LiveWallpaper.qml');
  const showExpr = qml.match(/readonly property bool showStill: (.*)/)[1];
  const wantExpr = qml.match(/readonly property string want: (.*)/)[1];
  const rootProps = { video: '/loop.mp4', viaMpv: true, obscured: false, batteryOk: true, ...overrides.root };
  const scope = {
    ...rootProps,
    root: rootProps,
    WallFx: { liveHeld: false, ...overrides.WallFx },
    ctl: { video: '/loop.mp4', running: false, again: false, wanted: '', command: [], ...overrides.ctl },
    slot: {
      modelData: { name: 'DP-3' },
      slotObscured: false,
      shouldPlay: true,
      released: false,
      sent: 'play /loop.mp4',
      frozenPath: '',
      ...overrides.slot,
    },
  };
  scope.shouldPlay = scope.slot.shouldPlay;
  scope.frozenPath = scope.slot.frozenPath;
  scope.slot.want = new Function('s', `with(s){return ${wantExpr}}`)(scope);
  scope.slot.showStill = new Function('s', `with(s){return ${showExpr}}`)(scope);
  functions('shell/modules/wallpaper/LiveWallpaper.qml', ['parseFrozen'], scope);
  return scope;
}

test('a paused or cover-released live wallpaper shows its frozen frame until playback resumes', () => {
  const playing = liveSlot({ slot: { frozenPath: '/run/frozen-DP-3.jpg', shouldPlay: true, released: false, sent: 'play /loop.mp4' } });
  expect(playing.slot.want).toBe('play');
  expect(playing.slot.showStill).toBe(false);

  const paused = liveSlot({ slot: { frozenPath: '/run/frozen-DP-3.jpg', shouldPlay: false, released: false, sent: 'pause /loop.mp4' } });
  expect(paused.slot.want).toBe('pause');
  expect(paused.slot.showStill).toBe(true);

  const released = liveSlot({ slot: { frozenPath: '/run/frozen-DP-3.jpg', shouldPlay: false, released: true, sent: 'stop' } });
  expect(released.slot.want).toBe('stop');
  expect(released.slot.showStill).toBe(true);

  const resuming = liveSlot({ slot: { frozenPath: '/run/frozen-DP-3.jpg', shouldPlay: true, released: false, sent: 'stop' } });
  expect(resuming.slot.want).toBe('play');
  expect(resuming.slot.showStill).toBe(true);

  const obscured = liveSlot({ slot: { frozenPath: '/run/frozen-DP-3.jpg', slotObscured: true, shouldPlay: false, released: true, sent: 'stop' } });
  expect(obscured.slot.showStill).toBe(false);
});

test('parseFrozen records only the matching screen for the current video', () => {
  const s = liveSlot();
  s.parseFrozen('eDP-1 /run/frozen-eDP-1.jpg\nDP-3 /run/frozen-DP-3.jpg\n');
  expect(s.slot.frozenPath).toBe('/run/frozen-DP-3.jpg');

  const stale = liveSlot({ root: { video: '/new.mp4' }, ctl: { video: '/old.mp4' } });
  stale.parseFrozen('DP-3 /run/frozen-DP-3.jpg\n');
  expect(stale.slot.frozenPath).toBe('');
});
