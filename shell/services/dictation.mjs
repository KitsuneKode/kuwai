export const WORDS_WAIT_MS = 400;
export const QUIET_AFTER_MS = 3000;
export const SILENT_AFTER_MS = 2500;
export const SPEECH = 0.3;
export const SIGNAL = 0.0003;
export const PENDING_MS = 10 * 60000;
export const LIVE_CHARS = 400;
export const LINE_CHARS = 160;
export const BARS = 5;

export const HOLD_MS = {
    delivered: 1800, clipboard: 5000, recovered: 12000, private: 2600,
    cancelled: 1400, nothing: 2200, silent: 4500, failed: 4500, untyped: 5000
};

const KINDS = {
    ok: 'delivered', delivered: 'delivered', output_complete: 'delivered',
    clipboard_only: 'clipboard', recovered: 'recovered', private_not_inserted: 'private',
    cancelled: 'cancelled', no_speech: 'nothing', too_short: 'nothing', empty: 'nothing',
    no_input: 'silent', error: 'failed', failed: 'failed', output_failed: 'untyped'
};

export const ENDINGS = Object.keys(HOLD_MS);
export const LIVE = ['listening', 'quiet', 'muted', 'silent-mic'];

export function ending(record, take) {
    if (!record || typeof record !== 'object') return null;
    const kind = KINDS[String(record.outcome || '')];
    if (!kind) return null;
    const at = Number(record.at_ms) || 0;
    const since = Number(take && take.since) || 0;
    if (!(at >= since - 1000)) return null;
    const id = String((take && take.id) || '');
    if (record.take_id && id && String(record.take_id) !== id) return null;
    return { kind, at, take: String(record.take_id || ''), chars: Number(record.chars) || 0, limit: record.limit_reached === true };
}

export function holdFor(kind) {
    return HOLD_MS[kind] || 0;
}

export function listening(state) {
    return state === 'recording' || state === 'streaming';
}

export function phase(s) {
    if (listening(s.state)) return s.muted ? 'muted' : s.silent ? 'silent-mic' : s.quiet ? 'quiet' : 'listening';
    if (s.state === 'transcribing') return 'writing';
    if (s.ending && HOLD_MS[s.ending.kind]) return s.ending.kind;
    return '';
}

export function tooQuiet(s) {
    return s.elapsed >= QUIET_AFTER_MS && !s.text && !(s.lastSpeech > 0 && s.now - s.lastSpeech < QUIET_AFTER_MS - 500);
}

export function micSilent(s) {
    return s.feeding && s.elapsed >= SILENT_AFTER_MS && !(s.lastSignal > 0);
}

export function appName(cls, desktopName) {
    let name = String(desktopName || '').trim();
    if (!name) {
        const c = String(cls || '').trim();
        if (!c) return '';
        const last = c.split('.').pop().replace(/[-_]+/g, ' ').replace(/([a-z])([A-Z])/g, '$1 $2').trim();
        name = last.charAt(0).toUpperCase() + last.slice(1);
    }
    return name.length > 24 ? name.slice(0, 23) + '…' : name;
}

export function tail(text, n) {
    const t = String(text || '').replace(/\s+/g, ' ').trim();
    const max = n || LIVE_CHARS;
    if (t.length <= max) return t;
    const cut = t.indexOf(' ', t.length - max);
    return '…' + t.slice(cut > 0 ? cut + 1 : t.length - max);
}

export function firstLine(text) {
    const line = String(text || '').split(/\r?\n/).map(x => x.trim()).find(x => x) || '';
    return line.length > LINE_CHARS ? line.slice(0, LINE_CHARS - 1) + '…' : line;
}

export function finalText(raw, since) {
    const s = String(raw || '');
    const nl = s.indexOf('\n');
    if (nl <= 0) return '';
    const at = Number(s.slice(0, nl)) || 0;
    if (!(at >= (Number(since) || 0) - 100)) return '';
    return s.slice(nl + 1).trim();
}

export function words(s) {
    if (s.phase === 'recovered') return { mode: 'note', text: 'Click to bring it back' };
    if (s.hidden || s.inField) return { mode: '', text: '' };
    if (s.phase === 'delivered' || s.phase === 'clipboard') {
        const line = firstLine(s.final);
        return line ? { mode: 'final', text: line } : { mode: '', text: '' };
    }
    if ((LIVE.indexOf(s.phase) >= 0 || s.phase === 'writing') && s.open && s.text)
        return { mode: 'live', text: tail(s.text) };
    return { mode: '', text: '' };
}

export function said(phase, app, why) {
    const to = app ? ' into ' + app : '';
    switch (phase) {
    case 'listening': return app;
    case 'private-listening': return app ? 'Private · ' + app : 'Private take';
    case 'quiet': return 'Too quiet';
    case 'muted': return 'Mic is muted';
    case 'silent-mic': return 'No sound from the mic';
    case 'writing': return 'Writing';
    case 'delivered': return 'Typed' + to;
    case 'clipboard': return 'Copied · paste it';
    case 'recovered': return 'Kept · the window changed';
    case 'private': return 'Private · not typed';
    case 'cancelled': return 'Cancelled · nothing typed';
    case 'nothing': return 'Didn’t hear anything';
    case 'silent': return 'The mic sent no sound';
    case 'failed': return why === 'limit' ? 'Too long to write out' : 'Couldn’t write that out';
    case 'untyped': return 'Couldn’t type it' + to;
    }
    return '';
}

export function tone(phase) {
    if (phase === 'listening') return 'red';
    if (phase === 'quiet' || phase === 'muted' || phase === 'silent-mic' || phase === 'recovered' || phase === 'clipboard') return 'orange';
    if (phase === 'delivered') return 'green';
    if (phase === 'failed' || phase === 'untyped' || phase === 'silent') return 'red';
    if (phase === 'writing') return 'accent';
    return 'quiet';
}

export function glyph(phase) {
    switch (phase) {
    case 'muted': return 'microphone-slash';
    case 'silent-mic': case 'silent': return 'microphone-slash';
    case 'delivered': return 'check';
    case 'clipboard': return 'clipboard-text';
    case 'recovered': return 'arrow-u-up-left';
    case 'private': return 'lock-simple';
    case 'cancelled': case 'nothing': return 'x';
    case 'failed': case 'untyped': return 'warning-circle';
    }
    return '';
}

export function started(pending, id, now) {
    const keep = (pending || []).filter(p => p && p.id !== id && now - p.at < PENDING_MS);
    return id ? keep.concat([{ id: String(id), at: now }]) : keep;
}

export function finished(pending, id) {
    return (pending || []).filter(p => p && p.id !== String(id || ''));
}

export function waiting(pending, state, current) {
    if (!state || state === 'idle') return 0;
    return (pending || []).filter(p => p && p.id !== String(current || '')).length;
}

export function ripple(history, level) {
    const h = [Math.max(0, Math.min(1, Number(level) || 0))].concat(history || []).slice(0, 2 * (BARS >> 1) + 1);
    return h;
}

export function bars(history) {
    const shape = [0.55, 0.8, 1, 0.8, 0.55];
    const h = history || [];
    const mid = BARS >> 1;
    const out = [];
    for (let i = 0; i < BARS; i++) {
        const d = Math.abs(i - mid);
        const v = h.length > 2 * d ? h[2 * d] : (h[0] || 0);
        out.push(Math.max(0, Math.min(1, Math.sqrt(v) * shape[i])));
    }
    return out;
}

export function clock(ms) {
    const s = Math.max(0, Math.floor((Number(ms) || 0) / 1000));
    return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
}
