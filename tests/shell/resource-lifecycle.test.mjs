import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { functions } from '../helpers/qml.mjs';

const wallpaperPath = 'shell/modules/wallpaper/LiveWallpaper.qml';
const source = path => readFileSync(new URL('../../' + path, import.meta.url), 'utf8');

function loadsWallpaper(state) {
  const qml = source(wallpaperPath);
  const scope = { root: {video:'/loop.mp4', locked:false, ...state.root}, Saver:{locked:false, screensOff:false, showing:false, ...state.Saver}, fadeOut:false };
  const obscured = qml.match(/readonly property bool obscured: (.*)/);
  if (obscured) scope.root.obscured = new Function('s', `with(s){return ${obscured[1]}}`)(scope);
  return new Function('s', `with(s){return ${qml.match(/^\s*active: (.*)/m)[1]}}`)(scope);
}

test('wallpaper resources unload while the saver, lock, or display power-off hides them', () => {
  expect(loadsWallpaper({})).toBe(true);
  expect(loadsWallpaper({root:{video:''}})).toBe(false);
  for (const property of ['locked','showing','screensOff']) expect(loadsWallpaper({Saver:{[property]:true}})).toBe(false);
  expect(loadsWallpaper({root:{locked:true}})).toBe(false);
});

const clipboardPath = 'shell/services/Clipboard.qml';
function clipboard() {
  return functions(clipboardPath, ['ref','retainPreviewRefs','syncPreviews','beginThumb','finishThumb'], {
    previewRefs: new Set(['1','2','pin:saved']),
    previewOwners: {}, thumbs:{}, thumbRetryAt:{}, pending:{}, fileInfo:{}, renders:{},
    Theme:{panelPollMs:5000},
  });
}

test('clipboard caches keep only active history and pins after hundreds of replacements', () => {
  const c = clipboard();
  for (let i = 1; i <= 500; i++) {
    const key = String(i);
    c.previewRefs = new Set([key, 'pin:saved']);
    c.syncPreviews();
    for (const name of ['thumbs','fileInfo','renders','thumbRetryAt']) c[name][key] = 'payload';
  }
  for (const name of ['thumbs','fileInfo','renders','thumbRetryAt']) expect(Object.keys(c[name])).toEqual(['500']);
  expect(Object.keys(c.previewOwners)).toEqual(['500','pin:saved']);
});

test('obsolete thumbnail completion cannot populate a reused clipboard id', () => {
  const c = clipboard(); c.syncPreviews();
  const old = {}, next = {};
  expect(c.beginThumb('1', () => old)).toBe(old);
  c.previewRefs = new Set(['2']); c.syncPreviews();
  c.previewRefs = new Set(['1','2']); c.syncPreviews();
  expect(c.beginThumb('1', () => next)).toBe(next);
  expect(c.finishThumb('1', old, '/old.png')).toBe(false);
  expect(c.thumbs['1']).toBeUndefined();
  expect(c.finishThumb('1', next, '/current.png')).toBe(true);
  expect(c.thumbs['1']).toBe('file:///current.png');
  expect(c.pending['1']).toBeUndefined();
});

test('a failed thumbnail can retry after backoff and does not hold an active request', () => {
  const c = clipboard(); c.syncPreviews();
  const request = {};
  expect(c.beginThumb('1', () => request)).toBe(request);
  expect(c.finishThumb('1', request, '')).toBe(true);
  expect(c.pending['1']).toBeUndefined();
  expect(c.beginThumb('1', () => ({}))).toBeNull();
  c.thumbRetryAt['1'] = 0;
  expect(c.beginThumb('1', () => ({}))).not.toBeNull();
});

function film() {
  const queue = [], kills = [];
  const movie = functions('shell/modules/screensaver/Screensaver.qml', ['syncFilm','filmExited'], {
    wantedFilm:'', activeFilm:'', filmStopping:false, clipFailed:false, filmOnCpu:false,
    filmProc:{running:false, signal(n){kills.push(n);}}, Qt:{callLater(cb){queue.push(cb);}}, console:{warn(){}},
  });
  function exit(code = 1) {
    movie.filmProc.running = false;
    movie.filmExited(code);
    for (const cb of queue.splice(0)) cb();
  }
  return {movie, kills, exit};
}

test('changing a playing saver film replaces it once and uses the latest choice', () => {
  const {movie, kills, exit} = film();
  movie.wantedFilm = '/old.mp4'; movie.syncFilm();
  expect(movie.activeFilm).toBe('/old.mp4');
  movie.wantedFilm = '/new.mp4'; movie.syncFilm();
  movie.wantedFilm = '/latest.mp4'; movie.syncFilm();
  expect(kills).toEqual([9]);
  exit();
  expect(movie.clipFailed).toBe(false);
  expect(movie.activeFilm).toBe('/latest.mp4');
  expect(movie.filmProc.running).toBe(true);
});

test('a failed live saver film falls back instead of keeping an empty film surface', () => {
  const {movie, exit} = film();
  Object.defineProperty(movie, 'wantedFilm', {get:()=>movie.clipFailed ? '' : '/missing.mp4'});
  movie.syncFilm();
  exit();   // the GPU's decoder: one more try, on the CPU
  expect(movie.clipFailed).toBe(false);
  exit();   // the CPU too: Dusk
  expect(movie.clipFailed).toBe(true);
  expect(movie.filmProc.running).toBe(false);
  expect(movie.activeFilm).toBe('');
});

test('an intentionally stopped film does not relaunch after dismissal', () => {
  const {movie, kills, exit} = film();
  movie.wantedFilm = '/loop.mp4'; movie.syncFilm();
  movie.wantedFilm = ''; movie.syncFilm();
  exit();
  expect(kills).toEqual([9]);
  expect(movie.clipFailed).toBe(false);
  expect(movie.filmProc.running).toBe(false);
});


test('carried notifications without an owner are released and matches keep actions', () => {
  const dead = [], item = {nid:1, notification:null}, existing = {id:3};
  const n = functions('shell/services/Notifs.qml', ['attachCarried'], {items:[item], snoozed:[{nid:3,notification:existing}]});
  const note = id => ({id, dismiss(){dead.push(id);}});
  const matched = note(1);
  n.attachCarried(matched);
  n.attachCarried(matched);
  n.attachCarried(note(2));
  n.attachCarried(note(3));
  expect(item.notification).toBe(matched);
  expect(n.snoozed[0].notification).toBe(existing);
  expect(dead).toEqual([2,3]);
});


test('committing deletion clears the card while the helper is still pending', () => {
  const calls = [];
  const c = functions(clipboardPath, ['purge'], {
    lastTop:'gone', expiring:[{id:'gone'}], raw:[{id:'gone'},{id:'keep'}],
    forgetSecret(){}, run(args){calls.push(args);}, setRaw(list){c.raw=list;}, saveState(){},
  });
  c.purge(['gone'], []);
  expect(c.raw).toEqual([{id:'keep'}]);
  expect(c.expiring).toEqual([]);
  expect(calls).toEqual([['delete','gone']]);
});

test('older file metadata cannot replace a newer reply', () => {
  const pending = [];
  const c = functions(clipboardPath, ['ref','files'], {
    previewOwners:{'1':{}}, fileInfo:{}, capture(args, cb){pending.push(cb);},
  });
  c.files({id:'1',pin:''}); c.files({id:'1',pin:''});
  pending[1]('[{"name":"new"}]'); pending[0]('[{"name":"old"}]');
  expect(c.fileInfo['1']).toEqual([{name:'new'}]);
});


test('a pick during a wallpaper change waits its turn, and only the newest one plays next', () => {
  const calls = [];
  const s = functions('shell/services/WallFx.qml', ['play'], { phase:'revealing', startFn:() => calls.push('old'), queued:null });
  s.play('/second.png', () => calls.push('second'));
  s.play('/third.png', () => calls.push('third'), true);
  expect(s.phase).toBe('revealing');
  expect(calls).toEqual([]);
  expect(s.queued.path).toBe('/third.png');
  expect(s.queued.live).toBe(true);
});


test('the saver scene and its timer are suppressed while locked or displays are off', () => {
  const qml = source('shell/modules/screensaver/Screensaver.qml');
  const expression = qml.match(/readonly property bool showing: ([\s\S]+?)\n\n/)[1];
  const isShowing = new Function('s', `with(s){return ${expression}}`);
  const state = {forced:true, allowed:true, fullscreenAnywhere:false, idleShown:true, wakeGrace:false, dismissed:false};
  expect(isShowing({...state, Saver:{locked:false, screensOff:false}})).toBe(true);
  expect(isShowing({...state, Saver:{locked:true, screensOff:false}})).toBe(false);
  expect(isShowing({...state, Saver:{locked:false, screensOff:true}})).toBe(false);
});

test('a media key keeps the saver up: the moment after waking holds it, then only a media change keeps it', () => {
  const qml = source('shell/modules/screensaver/Screensaver.qml');
  const expression = qml.match(/readonly property bool showing: ([\s\S]+?)\n\n/)[1];
  const isShowing = new Function('s', `with(s){return ${expression}}`);
  const woke = {forced:false, allowed:true, fullscreenAnywhere:false, idleShown:false, dismissed:false, Saver:{locked:false, screensOff:false}, Idle:{appHeld:false}};
  expect(isShowing({...woke, wakeGrace:true})).toBe(true);
  expect(isShowing({...woke, wakeGrace:false})).toBe(false);
  expect(isShowing({...woke, wakeGrace:true, Saver:{locked:true, screensOff:false}})).toBe(false);
  expect(qml).toMatch(/function mediaTouched\(\) \{ if \(!wakeGrace\) return; graceEnd\.stop\(\); wakeGrace = false; forced = true; \}/);
  expect(qml).toMatch(/function dismiss\(\) \{ forced = false; wakeGrace = false; dismissed = true; \}/);
});

test('a film the GPU decoder refuses plays again decoded on the CPU, once', () => {
  const {movie, exit} = film();
  movie.wantedFilm = '/night.mp4'; movie.syncFilm();
  expect(movie.filmOnCpu).toBe(false);
  exit();
  expect(movie.filmOnCpu).toBe(true);
  expect(movie.clipFailed).toBe(false);
  expect(movie.activeFilm).toBe('/night.mp4');
  expect(movie.filmProc.running).toBe(true);
});

test('the CPU retry is asked for in the film process environment', () => {
  const src = source('shell/modules/screensaver/Screensaver.qml');
  expect(src).toMatch(/root\.filmOnCpu\s*\?\s*\(\{[^}]*QT_FFMPEG_DECODING_HW_DEVICE_TYPES: "none"/);
  // A showing forgets a failure, not what the decoder taught: retrying the GPU each showing
  // cut every film at its first loop (the extra allocation is asked for there).
  expect(src).toMatch(/function filmFresh\(\) \{ clipFailed = false; \}/);
  expect(src).toMatch(/test -r "\$KUWAI_SAVER_FILE" \|\| exit 66/);
  expect(src).toMatch(/onExited: \(exitCode, exitStatus\) => root\.filmExited\(exitCode\)/);
});

test('once the CPU decodes films, a later failure goes to Dusk without asking the GPU again', () => {
  const {movie, exit} = film();
  movie.wantedFilm = '/night.mp4'; movie.syncFilm();
  exit();                                   // stopped on the GPU at its first loop
  expect(movie.filmOnCpu).toBe(true);
  exit();                                   // and on the CPU
  expect(movie.filmOnCpu).toBe(true);
  expect(movie.clipFailed).toBe(true);
});

test('a missing film goes straight to Dusk, with no CPU retry', () => {
  const {movie, exit} = film();
  Object.defineProperty(movie, 'wantedFilm', {get:()=>movie.clipFailed ? '' : '/gone.mp4'});
  movie.syncFilm();
  exit(66);
  expect(movie.filmOnCpu).toBe(false);
  expect(movie.clipFailed).toBe(true);
  expect(movie.filmProc.running).toBe(false);
});

test('a film with no picture in it goes straight to Dusk, with no CPU retry', () => {
  const {movie, exit} = film();
  Object.defineProperty(movie, 'wantedFilm', {get:()=>movie.clipFailed ? '' : '/broken.mp4'});
  movie.syncFilm();
  exit(65);
  expect(movie.filmOnCpu).toBe(false);
  expect(movie.clipFailed).toBe(true);
  expect(movie.filmProc.running).toBe(false);
});

test('mpv plays the saver film once for every screen, refusing what it could not open', () => {
  const src = source('shell/modules/screensaver/Screensaver.qml');
  // One mpvpaper on '*' (one decoder for every screen; Qt's player had one per screen: 888 MiB).
  expect(src).toMatch(/exec setpriv --pdeathsig KILL mpvpaper -l top -o "\$1" "\*" "\$KUWAI_SAVER_FILE"/);
  // mpvpaper waits forever on a file mpv can't open: refused before it starts.
  expect(src).toMatch(/ffprobe [^']*\|\| exit 65/);
  // Copy-back decoding, or none on the GPU once the CPU was learnt; never your mpv config.
  expect(src).toMatch(/hwdec=" \+ \(filmOnCpu \? "no" : "auto-copy-safe"\)/);
  expect(src).toMatch(/MPV_HOME="\$home"/);
  // A film left over from an earlier shell goes, and only the saver's (-l top) player.
  expect(src).not.toMatch(/pkill/);
  expect(src).toMatch(/exec setpriv --pdeathsig KILL mpvpaper/);
  // It starts once the screen is dark; the black over it lifts once it plays.
  expect(src).toMatch(/wantedFilm: showing && darkened && !longDark \? film : ""/);
  expect(src).toMatch(/input-ipc-server=" \+ ipcPath/);
  expect(src).toMatch(/observe_property",1,"playback-time"/);
  expect(src).toMatch(/m\.name === "playback-time" && typeof m\.data === "number" && m\.data > 0\) \{\s*root\.reveal\(\)/);
  expect(src).not.toMatch(/onStarted: coverOut\.restart\(\)/);
  expect(src).toMatch(/waited >= 8000\) \{[\s\S]*?filmProc\.signal\(9\)/);
  expect(src).toMatch(/readonly property bool filmHere: root\.film !== ""/);
});
