import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import * as D from '../../shell/services/dictation.mjs';

const take = { id: '1795883552041990133', since: 1795883552206 };
const record = (over) => ({ outcome: 'delivered', take_id: take.id, session_started_at_ms: take.since, chars: 42, limit_reached: false, at_ms: take.since + 9000, ...over });

describe('how a take ended', () => {
  test('voxtype’s outcomes become the island’s endings', () => {
    const cases = { ok: 'delivered', delivered: 'delivered', output_complete: 'delivered', clipboard_only: 'clipboard',
      recovered: 'recovered', private_not_inserted: 'private', cancelled: 'cancelled', no_speech: 'nothing', too_short: 'nothing',
      empty: 'nothing', no_input: 'silent', error: 'failed', failed: 'failed', output_failed: 'untyped' };
    for (const [outcome, kind] of Object.entries(cases)) expect(D.ending(record({ outcome }), take).kind).toBe(kind);
  });
  test('an outcome from an earlier take or another take is not this one’s', () => {
    expect(D.ending(record({ at_ms: take.since - 60000 }), take)).toBeNull();
    expect(D.ending(record({ take_id: '17' }), take)).toBeNull();
    expect(D.ending(record({ take_id: undefined }), take).kind).toBe('delivered');
    expect(D.ending(record({ outcome: 'something new' }), take)).toBeNull();
    expect(D.ending(null, take)).toBeNull();
  });
  test('a take cut by the time limit says so', () => {
    const e = D.ending(record({ outcome: 'error', limit_reached: true }), take);
    expect(D.said('failed', '', e.limit ? 'limit' : '')).toBe('Too long to write out');
  });
  test('each ending holds long enough to read, the one to act on longest', () => {
    for (const k of D.ENDINGS) expect(D.holdFor(k)).toBeGreaterThan(1000);
    expect(D.holdFor('recovered')).toBeGreaterThan(D.holdFor('failed'));
    expect(D.holdFor('delivered')).toBeLessThan(D.holdFor('failed'));
  });
});

describe('the phase the island shows', () => {
  test('listening, and the three ways it goes wrong, in order of what to fix first', () => {
    expect(D.phase({ state: 'recording' })).toBe('listening');
    expect(D.phase({ state: 'streaming', quiet: true })).toBe('quiet');
    expect(D.phase({ state: 'streaming', quiet: true, silent: true })).toBe('silent-mic');
    expect(D.phase({ state: 'streaming', quiet: true, silent: true, muted: true })).toBe('muted');
  });
  test('writing, then the ending, then nothing', () => {
    expect(D.phase({ state: 'transcribing', ending: { kind: 'delivered' } })).toBe('writing');
    expect(D.phase({ state: 'idle', ending: { kind: 'delivered' } })).toBe('delivered');
    expect(D.phase({ state: 'idle', ending: null })).toBe('');
    expect(D.phase({ state: 'review', ending: null })).toBe('');
  });
  test('too quiet: three seconds in, no words, no voice lately', () => {
    expect(D.tooQuiet({ elapsed: 2900, text: '', lastSpeech: 0, now: 10000 })).toBe(false);
    expect(D.tooQuiet({ elapsed: 3200, text: '', lastSpeech: 0, now: 10000 })).toBe(true);
    expect(D.tooQuiet({ elapsed: 3200, text: 'so', lastSpeech: 0, now: 10000 })).toBe(false);
    expect(D.tooQuiet({ elapsed: 3200, text: '', lastSpeech: 9500, now: 10000 })).toBe(false);
  });
  test('a mic that sends nothing is told apart from a quiet one only when it is being read', () => {
    expect(D.micSilent({ feeding: true, elapsed: 3000, lastSignal: 0 })).toBe(true);
    expect(D.micSilent({ feeding: false, elapsed: 3000, lastSignal: 0 })).toBe(false);
    expect(D.micSilent({ feeding: true, elapsed: 3000, lastSignal: 5 })).toBe(false);
  });
});

describe('words: one place, never twice, never private', () => {
  const base = { phase: 'listening', hidden: false, inField: false, open: true, text: 'so the idea is we cache the tokens', final: '' };
  test('where the field can’t show them, the island does', () => {
    expect(D.words(base)).toEqual({ mode: 'live', text: base.text });
    expect(D.words({ ...base, phase: 'writing' }).mode).toBe('live');
  });
  test('where the field shows them, the island shows none, at delivery too', () => {
    expect(D.words({ ...base, inField: true }).mode).toBe('');
    expect(D.words({ ...base, inField: true, phase: 'delivered', final: 'Done.' }).mode).toBe('');
  });
  test('a private take or a shared screen: no words, ever', () => {
    for (const phase of ['listening', 'writing', 'delivered']) expect(D.words({ ...base, phase, hidden: true, final: 'secret' }).mode).toBe('');
  });
  test('not before the field has had its moment to say it shows them', () => {
    expect(D.words({ ...base, open: false }).mode).toBe('');
  });
  test('delivered: the first line of what was typed', () => {
    expect(D.words({ ...base, phase: 'delivered', final: '\n  Ship it on Friday.\nSecond line' })).toEqual({ mode: 'final', text: 'Ship it on Friday.' });
    expect(D.words({ ...base, phase: 'delivered', final: '' }).mode).toBe('');
  });
  test('a kept take says how to bring it back, with no words in it', () => {
    expect(D.words({ ...base, phase: 'recovered', hidden: true })).toEqual({ mode: 'note', text: 'Click to bring it back' });
  });
  test('a long take keeps its newest words, cut at a word', () => {
    const long = Array.from({ length: 200 }, (_, i) => 'word' + i).join(' ');
    const t = D.tail(long);
    expect(t.length).toBeLessThanOrEqual(D.LIVE_CHARS + 1);
    expect(t.endsWith('word199')).toBe(true);
    expect(t.startsWith('…word')).toBe(true);
  });
  test('the cleaned text is this take’s only', () => {
    expect(D.finalText('1795883560000\nHello there.', take.since)).toBe('Hello there.');
    expect(D.finalText('1795880000000\nOld take.', take.since)).toBe('');
    expect(D.finalText('garbage', take.since)).toBe('');
  });
});

describe('what it says', () => {
  test('where the text goes, in the app’s own name', () => {
    expect(D.appName('com.t3tools.T3Code', 'T3 Code')).toBe('T3 Code');
    expect(D.appName('kitty', '')).toBe('Kitty');
    expect(D.appName('org.kde.dolphin', '')).toBe('Dolphin');
    expect(D.appName('', '')).toBe('');
    expect(D.appName('x', 'An application with a very long name indeed').length).toBe(24);
    expect(D.said('delivered', 'Kitty')).toBe('Typed into Kitty');
    expect(D.said('delivered', '')).toBe('Typed');
    expect(D.said('listening', 'T3 Code')).toBe('T3 Code');
  });
  test('every phase has words, a tone and (for an ending) a mark', () => {
    for (const p of D.LIVE.concat(['writing'], D.ENDINGS)) {
      expect(D.said(p, 'Kitty') || p === 'listening').toBeTruthy();
      expect(D.tone(p)).toBeTruthy();
    }
    for (const p of D.ENDINGS) expect(D.glyph(p)).toBeTruthy();
  });
  test('no helper names, exit codes or paths', () => {
    for (const p of D.LIVE.concat(['writing'], D.ENDINGS)) expect(D.said(p, 'Kitty')).not.toMatch(/voxtype|shuush|exit|\/|code \d/i);
  });
  test('the clock', () => {
    expect(D.clock(0)).toBe('0:00');
    expect(D.clock(65400)).toBe('1:05');
  });
});

describe('takes waiting to be written', () => {
  test('counted from the takes that started and have not ended, without the one in hand', () => {
    let p = D.started([], 'a', 1000);
    p = D.started(p, 'b', 2000);
    expect(D.waiting(p, 'recording', 'b')).toBe(1);
    p = D.finished(p, 'a');
    expect(D.waiting(p, 'recording', 'b')).toBe(0);
    expect(D.waiting(D.started(p, 'c', 3000), 'idle', 'c')).toBe(0);
  });
  test('a take whose end was never seen is forgotten', () => {
    const p = D.started(D.started([], 'a', 0), 'b', D.PENDING_MS + 1);
    expect(p.map(x => x.id)).toEqual(['b']);
  });
});

describe('the waveform', () => {
  test('five bars, loudest in the middle, a syllable spreading outwards', () => {
    let h = [];
    h = D.ripple(h, 1);
    const first = D.bars(h);
    expect(first.length).toBe(D.BARS);
    expect(first[2]).toBeGreaterThan(first[0]);
    for (let i = 0; i < 4; i++) h = D.ripple(h, 0);
    expect(D.bars(h)[2]).toBe(0);
    expect(D.bars(h)[0]).toBeGreaterThan(0);
  });
  test('quiet is flat', () => {
    expect(D.bars([]).every(v => v === 0)).toBe(true);
  });
});

describe('wiring', () => {
  const read = p => readFileSync(new URL('../../shell/' + p, import.meta.url), 'utf8');
  test('the island hosts dictation by default and its words never repeat the field', () => {
    const schema = JSON.parse(read('config/settings-schema.json'));
    const e = schema.settings.find(s => s.key === 'dictationPill');
    expect(e.default).toBe('island');
    expect(e.enum[0]).toBe('island');
    expect(read('modules/voxtype/VoxtypeHost.qml')).toContain('sh.state.osdSuppressed || Settings.dictationPill === "island"');
  });
  test('the dictation panel never takes the keyboard from the window the words go to', () => {
    expect(read('services/Island.qml')).toContain('readonly property bool keyless: previewing || panel === "dictation"');
    const bar = read('modules/island/IslandBar.qml');
    expect(bar).toContain('(panelHere && !Island.keyless)');
    expect(bar).toContain('active: win.panelHere && win.armed && !Island.keyless');
    expect(bar).not.toContain('!Island.previewing');
    expect(read('services/KeyOwner.qml')).toContain('!Island.keyless');
  });
  test('words from outside are plain text', () => {
    for (const f of ['modules/island/DictationWords.qml', 'modules/island/DictationPanel.qml', 'modules/island/DictationMark.qml'])
      expect(read(f)).not.toMatch(/textFormat:\s*Text\.(RichText|StyledText|MarkdownText)/);
  });
});
