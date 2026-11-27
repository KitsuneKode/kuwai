import { expect, test } from 'bun:test';
import { execFileSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { functions } from '../helpers/qml.mjs';
import * as Outcome from '../../shell/services/wallOutcome.mjs';

const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

function timer() {
  return {
    running: false,
    restarts: 0,
    stops: 0,
    restart() { this.running = true; this.restarts++; },
    stop() { this.running = false; this.stops++; },
  };
}

function makeTheme(phaseRef) {
  const commits = [];
  const file = () => ({ loaded: false, body: '', text() { return this.body; } });
  const Qt = {
    color: s => typeof s === 'string' ? { hex: s.toLowerCase(), r: 0.1, g: 0.2, b: 0.3, hslHue: 0.6, hslSaturation: 0.8, hslLightness: 0.7 } : s,
    hsla: (h, s, l, a) => ({ hex: `hsla(${h},${s},${l},${a})` }),
    rgba: (r, g, b, a) => ({ hex: `rgba(${r},${g},${b},${a})` }),
    colorEqual: (a, b) => JSON.stringify(Qt.color(a)) === JSON.stringify(Qt.color(b)),
  };
  let accentVal = Qt.color('#0a84ff');
  const scope = {
    Qt,
    JSON,
    coloured: true,
    recolorHeld: false,
    recolorDirty: false,
    colorMode: 0,
    themeName: '',
    wallTopLuma: 0.1,
    palette: [],
    accentSoft: Qt.color('#0a84ff'),
    themeBg: Qt.color('#111114'),
    themeFg: Qt.color('#ffffff'),
    wallInk: Qt.color('#ffffff'),
    kuwaiPalette: file(),
    themeDcol: file(),
    themeKitty: file(),
    wallDcol: file(),
    recolorSettle: timer(),
    reduceMotion: false,
    textPrimary: 'white',
  };
  Object.defineProperty(scope, 'accent', {
    get: () => accentVal,
    set: v => { accentVal = v; commits.push({ phase: phaseRef(), hex: v.hex }); },
    enumerable: true,
  });
  functions('shell/config/Theme.qml', ['vivid', 'parseDcol', 'fromDcol', 'fromKitty', 'fromKuwaiLook', 'colours', 'commit', 'recolor', 'holdRecolor', 'flushRecolor'], scope);
  return { Theme: scope, commits };
}

function makeWallFx(screenNames = ['eDP-1', 'DP-3']) {
  const detached = [];
  const deferred = [];
  const moments = [];
  let fx = null;
  const { Theme, commits } = makeTheme(() => fx ? fx.phase : '');
  const screens = screenNames.map(name => ({ name }));
  const scope = {
    Outcome,
    Theme,
    Paths: { bin: '/bin', stateHome: '/state' },
    Settings: { wallTransition: 'glass' },
    Moments: { show: m => moments.push(m.label) },
    Quickshell: {
      screens,
      execDetached(cmd) { detached.push(cmd); },
    },
    Qt: { callLater(cb) { deferred.push(cb); } },
    phase: '',
    next: '',
    nextReal: '',
    before: {},
    known: false,
    ready: 0,
    t: 0,
    startFn: null,
    startedAt: 0,
    lastRun: '',
    mode: 'glass',
    mapPath: '',
    turn: 0,
    seed: 0,
    fade: 0,
    swapped: false,
    needMap: false,
    liveHeld: false,
    toLive: false,
    frozen: {},
    liveThumb: '',
    queued: null,
    shownBefore: {},
    failure: '',
    participants: [],
    targetOutputs: [],
    verifyTargets: [],
    scoped: false,
    readyScreens: {},
    liveProbe: { running: false },
    query: { running: false },
    check: { running: false },
    mapLookup: { running: false, command: [] },
    swap: { running: false, command: [] },
    verifier: { path: '', before: {}, targets: [], why: '', tries: 0, running: false },
    loadLimit: timer(),
    watchdog: timer(),
    settleLimit: timer(),
    handOff: timer(),
    go: timer(),
    recheck: timer(),
    landed: timer(),
    after: timer(),
    reveal: timer(),
    fadeIn: timer(),
    fadeOut: timer(),
    verifyLater: timer(),
  };
  fx = functions('shell/services/WallFx.qml', [
    'currentScreens', 'normalizeTargets', 'awwwCommand', 'sameParticipants', 'screensChanged', 'markReady',
    'play', 'cancelTransition', 'bail', 'drain', 'parse', 'cover',
    'enterSettling', 'leave', 'force', 'finish', 'unreadable', 'decodeFailed',
    'verify', 'verified',
  ], scope);
  const flushDeferred = () => { while (deferred.length) deferred.shift()(); };
  return { fx, Theme, commits, detached, moments, flushDeferred };
}

test('a change keeps a fixed participant set and only covers once every participant is ready', () => {
  const { fx } = makeWallFx(['eDP-1', 'DP-3']);
  fx.play('/w/new.jpg', () => {});
  expect(fx.phase).toBe('loading');
  expect(fx.participants).toEqual(['eDP-1', 'DP-3']);

  fx.markReady('HDMI-A-1');
  expect(fx.phase).toBe('loading');
  expect(fx.ready).toBe(0);

  fx.markReady('eDP-1');
  expect(fx.phase).toBe('loading');
  expect(fx.ready).toBe(1);

  fx.markReady('eDP-1');
  expect(fx.phase).toBe('loading');
  expect(fx.ready).toBe(1);

  fx.markReady('DP-3');
  expect(fx.phase).toBe('covered');
  expect(fx.fadeIn.running).toBe(true);
});

test('a monitor appearing or disappearing mid-change abandons cleanly to the plain switch', () => {
  for (const [label, nextScreens] of [
    ['added', ['eDP-1', 'DP-3', 'HDMI-A-1']],
    ['removed', ['eDP-1']],
    ['replaced', ['eDP-1', 'HDMI-A-1']],
  ]) {
    const { fx, Theme, detached } = makeWallFx(['eDP-1', 'DP-3']);
    const starts = [];
    fx.play('/w/new.jpg', () => starts.push(label));
    fx.markReady('eDP-1');
    fx.markReady('DP-3');
    expect(fx.phase).toBe('covered');

    fx.Quickshell.screens = nextScreens.map(name => ({ name }));
    fx.screensChanged();

    expect(fx.phase).toBe('');
    expect(fx.participants).toEqual([]);
    expect(fx.fadeIn.running).toBe(false);
    expect(fx.reveal.running).toBe(false);
    expect(Theme.recolorHeld).toBe(false);
    expect(starts).toEqual([label]);
    expect(fx.lastRun).toBe('fallback: monitors changed');
    expect(detached).toEqual([]);
  }
});

test('a monitor disappearing during revealing after handoff tears down the cover and ensures awww switches', () => {
  const { fx, detached } = makeWallFx(['eDP-1', 'DP-3']);
  let started = 0;
  fx.play('/w/new.jpg', () => { started++; });
  fx.phase = 'revealing';
  fx.startFn = null;
  fx.swapped = false;
  fx.Quickshell.screens = [{ name: 'eDP-1' }];
  fx.screensChanged();

  expect(fx.phase).toBe('');
  expect(started).toBe(0);
  expect(detached).toEqual([['awww', 'img', '/w/new.jpg', '--transition-type', 'none']]);
});

test('reordering the same outputs does not abandon an active reveal', () => {
  const { fx } = makeWallFx(['eDP-1', 'DP-3']);
  fx.play('/w/new.jpg', () => {});
  fx.phase = 'revealing';
  fx.Quickshell.screens = [{ name: 'DP-3' }, { name: 'eDP-1' }];
  fx.screensChanged();
  expect(fx.phase).toBe('revealing');
});

test('an unreadable new or current picture abandons cleanly in any phase', () => {
  const a = makeWallFx(['DP-3']);
  let plain = 0;
  a.fx.play('/w/bad.jpg', () => { plain++; });
  a.fx.shownBefore = { 'DP-3': '/w/old.jpg' };
  a.fx.unreadable('/w/bad.jpg');
  a.flushDeferred();
  expect(a.fx.phase).toBe('');
  expect(a.fx.failure).toBe('unreadable');
  expect(plain).toBe(1);
  expect(a.fx.verifyLater.restarts).toBe(1);

  const b = makeWallFx(['DP-3']);
  let plainB = 0;
  b.fx.play('/w/new.jpg', () => { plainB++; });
  b.fx.phase = 'covered';
  b.fx.decodeFailed('/w/old.jpg');
  b.flushDeferred();
  expect(b.fx.phase).toBe('');
  expect(b.fx.failure).toBe('');
  expect(plainB).toBe(1);
});

test('the picture and the accent land together inside the reveal settle phase', () => {
  const { fx, Theme, commits } = makeWallFx(['DP-3']);
  const qml = read('shell/services/WallFx.qml');
  expect(qml).toMatch(/id: handOff[\s\S]*?if \(root\.startFn\)/);

  fx.play('/w/new.jpg', () => {});
  expect(Theme.recolorHeld).toBe(true);
  fx.markReady('DP-3');
  fx.phase = 'revealing';
  fx.swapped = true;

  Theme.kuwaiPalette.loaded = true;
  Theme.kuwaiPalette.body = JSON.stringify({
    schema: 1,
    mode: 'dark',
    role: { accent: '#ff55aa', bg: '#111114' },
    swatches: ['#111114', '#ff55aa'],
    source: { name: 'Kuwai Night' },
  });
  Theme.recolor();
  expect(commits).toEqual([]);
  expect(Theme.recolorDirty).toBe(true);

  fx.enterSettling();
  expect(commits).toEqual([{ phase: 'settling', hex: '#ff55aa' }]);
  expect(Theme.recolorHeld).toBe(false);
  expect(fx.phase).toBe('leaving');
});

test('canonical path resolution compares realpath on both sides of awww query and target', () => {
  const dir = mkdtempSync(join(tmpdir(), 'kuwai-wallfx-real-'));
  try {
    const realOld = join(dir, 'old-real.png');
    const realNew = join(dir, 'new-real.png');
    const linkOld = join(dir, 'wall.set');
    const linkNew = join(dir, 'next-link.png');
    writeFileSync(realOld, 'old');
    writeFileSync(realNew, 'new');
    symlinkSync(realOld, linkOld);
    symlinkSync(realNew, linkNew);
    const canonOld = realpathSync(realOld);
    const canonNew = realpathSync(realNew);

    const fakeBin = join(dir, 'bin');
    execFileSync('mkdir', ['-p', fakeBin]);
    const awww = join(fakeBin, 'awww');
    writeFileSync(awww, '#!/bin/sh\nprintf ": DP-3: 2560x1440, currently displaying: image: %s\\n" "$FAKE_SHOWN"\n');
    chmodSync(awww, 0o755);

    const qml = read('shell/services/WallFx.qml');
    const m = qml.match(/id: verifier[\s\S]*?command: \["sh", "-c", '([^']+)', "sh", path\]/);
    expect(m).not.toBeNull();
    const script = m[1].replace(/\\\\n/g, '\\n');
    const runVerify = (shownPath, targetPath) => execFileSync('sh', ['-c', script, 'sh', targetPath], {
      env: { ...process.env, PATH: `${fakeBin}:/usr/bin:/bin`, FAKE_SHOWN: shownPath },
      encoding: 'utf8',
    });

    const outBefore = runVerify(linkOld, linkNew);
    const before = Outcome.parseShown(outBefore);
    expect(before).toEqual({ 'DP-3': canonOld });
    expect(Outcome.parseWanted(outBefore)).toBe(canonNew);

    const outSame = runVerify(realOld, linkOld);
    expect(Outcome.unchanged(before, Outcome.parseShown(outSame), Outcome.parseWanted(outSame))).toBe(false);

    const outStuckViaLink = runVerify(linkOld, realNew);
    expect(Outcome.unchanged(before, Outcome.parseShown(outStuckViaLink), Outcome.parseWanted(outStuckViaLink))).toBe(true);

    const outChangedViaLink = runVerify(linkNew, realNew);
    expect(Outcome.unchanged(before, Outcome.parseShown(outChangedViaLink), Outcome.parseWanted(outChangedViaLink))).toBe(false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a targeted per-screen play scopes participants, awww -o output, hotplug bailout, and verification', () => {
  const { fx, detached } = makeWallFx(['eDP-1', 'DP-3']);
  fx.play('/w/acer.jpg', () => {}, false, ['DP-3']);
  expect(fx.phase).toBe('loading');
  expect(fx.scoped).toBe(true);
  expect(fx.participants).toEqual(['DP-3']);
  expect(fx.targetOutputs).toEqual(['DP-3']);
  expect(fx.awwwCommand('/w/acer.jpg', fx.targetOutputs)).toEqual(['awww', 'img', '-o', 'DP-3', '/w/acer.jpg', '--transition-type', 'none']);

  fx.markReady('eDP-1');
  expect(fx.phase).toBe('loading');
  fx.markReady('DP-3');
  expect(fx.phase).toBe('covered');

  fx.phase = 'revealing';
  fx.startFn = null;
  fx.swapped = false;
  fx.Quickshell.screens = [{ name: 'eDP-1' }, { name: 'DP-3' }, { name: 'HDMI-A-1' }];
  fx.screensChanged();
  expect(fx.phase).toBe('revealing');

  fx.Quickshell.screens = [{ name: 'eDP-1' }];
  fx.screensChanged();
  expect(fx.phase).toBe('');
  expect(detached).toEqual([['awww', 'img', '-o', 'DP-3', '/w/acer.jpg', '--transition-type', 'none']]);

  expect(Outcome.unchanged(
    { 'eDP-1': '/w/old.jpg', 'DP-3': '/w/old.jpg' },
    { 'eDP-1': '/w/old.jpg', 'DP-3': '/w/acer.jpg' },
    '/w/acer.jpg',
    ['DP-3'],
  )).toBe(false);
  expect(Outcome.unchanged(
    { 'eDP-1': '/w/old.jpg', 'DP-3': '/w/old.jpg' },
    { 'eDP-1': '/w/old.jpg', 'DP-3': '/w/old.jpg' },
    '/w/acer.jpg',
    ['DP-3'],
  )).toBe(true);
});
