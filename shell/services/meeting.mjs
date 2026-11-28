export const PENDING = ["starting", "pausing", "resuming", "stopping"];
export const STATES = ["idle", "starting", "recording", "pausing", "paused", "resuming", "stopping", "finalizing"];
export const OFFER_EARLY_MS = 60000;
export const OFFER_LATE_MS = 5 * 60000;
export const SUMMARY_WAIT_MS = 10 * 60000;
export const REQUEST_STALE_MS = 30000;
export const FORGET_OFFERS_MS = 2 * 86400000;

export function empty() {
    return {
        status: "idle", id: "", title: "", startedAt: 0, segments: [], notice: false,
        announces: false, announcement: null, echoCancel: "", mic: -1, loopback: -1, levelAt: 0,
        summary: null, summaryFor: "", summarizing: "", problem: "", problemCode: "", lastId: "", lastTitle: "", lastStartedAt: 0, endedAt: 0
    };
}

export function active(status) {
    return STATES.indexOf(status) > 0;
}

export function phase(status) {
    if (status === "recording" || status === "resuming") return "live";
    if (status === "paused" || status === "pausing") return "paused";
    if (status === "starting") return "starting";
    if (status === "stopping" || status === "finalizing") return "ending";
    return "off";
}

export function meter(db) {
    const n = Number(db);
    if (db === null || db === undefined || !Number.isFinite(n)) return -1;
    return Math.max(0, Math.min(1, (n + 60) / 60));
}

export function speakerName(seg) {
    if (!seg) return "";
    const label = typeof seg.speaker_label === "string" ? seg.speaker_label.trim() : "";
    return label || String(seg.speaker_id || "");
}

function clean(seg) {
    if (!seg || typeof seg !== "object") return null;
    const id = Number(seg.id);
    if (!Number.isFinite(id)) return null;
    const out = {
        id, start: Math.max(0, Number(seg.start_ms) || 0), end: Math.max(0, Number(seg.end_ms) || 0),
        text: String(seg.text || ""), source: seg.source === "loopback" ? "loopback" : "microphone",
        speakerId: String(seg.speaker_id || ""), label: typeof seg.speaker_label === "string" ? seg.speaker_label : ""
    };
    out.who = out.label.trim() || out.speakerId || (out.source === "microphone" ? "You" : "Call");
    out.you = out.speakerId === "You";
    if (seg.annotation && typeof seg.annotation === "object") out.note = { text: String(seg.annotation.text || ""), highlight: !!seg.annotation.highlight };
    return seg.deleted === true ? null : out;
}

export function place(segments, raw) {
    const seg = clean(raw);
    const rest = segments.filter(s => s.id !== Number(raw && raw.id));
    if (!seg) return rest;
    let i = rest.length;
    while (i > 0 && rest[i - 1].start > seg.start) i--;
    rest.splice(i, 0, seg);
    return rest;
}

export function absorb(segments, list) {
    let out = segments;
    for (const s of Array.isArray(list) ? list : []) out = place(out, s);
    return out;
}

function stamp(iso) {
    const t = Date.parse(String(iso || ""));
    return Number.isFinite(t) ? t : 0;
}

export function summaryOf(s) {
    if (!s || typeof s !== "object") return null;
    const items = Array.isArray(s.action_items) ? s.action_items : [];
    return {
        text: String(s.summary || ""),
        points: (Array.isArray(s.key_points) ? s.key_points : []).map(String).filter(x => x),
        decisions: (Array.isArray(s.decisions) ? s.decisions : []).map(String).filter(x => x),
        actions: items.filter(a => a && a.description).map(a => ({ text: String(a.description), who: String(a.assignee || ""), done: !!a.completed })),
        model: String(s.model || "")
    };
}

function ended(state) {
    if (!state.id) return state;
    return Object.assign({}, state, { lastId: state.id, lastTitle: state.title, lastStartedAt: state.startedAt });
}

export function apply(state, ev) {
    if (!ev || typeof ev !== "object" || typeof ev.event !== "string") return state;
    const s = Object.assign({}, state);
    switch (ev.event) {
    case "hello": {
        const status = STATES.indexOf(ev.status) >= 0 ? ev.status : "idle";
        if (status === "idle") {
            const was = ended(state);
            return Object.assign(empty(), { lastId: was.lastId, lastTitle: was.lastTitle, lastStartedAt: was.lastStartedAt, endedAt: state.endedAt, summary: state.summary, summaryFor: state.summaryFor, summarizing: state.summarizing });
        }
        s.status = status;
        s.id = String(ev.meeting_id || "");
        s.title = String(ev.title || "");
        s.startedAt = stamp(ev.started_at);
        s.segments = absorb([], ev.segments);
        s.notice = ev.recording_notice === true;
        s.announces = ev.announces === true;
        s.announcement = ev.announcement || null;
        s.echoCancel = String(ev.echo_cancel || "");
        s.problem = ""; s.problemCode = "";
        return s;
    }
    case "segments":
        s.segments = absorb(state.segments, ev.segments);
        if (s.problemCode === "track_not_transcribed") { s.problem = ""; s.problemCode = ""; }
        return s;
    case "segment_updated":
        s.segments = place(state.segments, ev.segment);
        return s;
    case "segment_deleted":
        s.segments = state.segments.filter(x => x.id !== Number(ev.segment_id));
        return s;
    case "speaker_renamed": {
        const from = String(ev.from || ""), to = String(ev.to || "");
        s.segments = state.segments.map(x => {
            if (x.speakerId !== from) return x;
            const y = Object.assign({}, x, { speakerId: to });
            y.who = y.label.trim() || to;
            y.you = to === "You";
            return y;
        });
        return s;
    }
    case "title_changed":
        if (!ev.meeting_id || ev.meeting_id === state.id) s.title = String(ev.title || "");
        return s;
    case "announcement":
        s.announcement = { state: String(ev.state || ""), text: String(ev.text || "") };
        return s;
    case "status": {
        if (ev.status === "summarizing") { s.summarizing = String(ev.meeting_id || state.lastId || state.id); return s; }
        if (STATES.indexOf(ev.status) < 0) return s;
        if (typeof ev.recording_notice === "boolean") s.notice = ev.recording_notice;
        if (ev.status === "idle" && active(state.status)) {
            const was = ended(state);
            return Object.assign(empty(), { lastId: was.lastId, lastTitle: was.lastTitle, lastStartedAt: was.lastStartedAt, endedAt: Date.now(), summary: state.summary, summaryFor: state.summaryFor, summarizing: state.summarizing, segments: state.segments });
        }
        s.status = ev.status;
        return s;
    }
    case "summary_ready":
        s.summary = summaryOf(ev.summary);
        s.summaryFor = String(ev.meeting_id || "");
        if (s.summarizing === s.summaryFor) s.summarizing = "";
        return s;
    case "levels":
        if (ev.soundcheck === true) return state;
        s.mic = meter(ev.mic);
        s.loopback = meter(ev.loopback);
        s.levelAt = Date.now();
        return s;
    case "error":
        if (ev.meeting_id && ev.meeting_id === state.summarizing) s.summarizing = "";
        s.problem = String(ev.message || "");
        s.problemCode = String(ev.code || "");
        return s;
    default:
        return state;
    }
}

export function parseLine(line) {
    const t = String(line || "").trim();
    if (!t || t[0] !== "{") return null;
    try { return JSON.parse(t); } catch (e) { return null; }
}

export function feedDone(state, now) {
    if (active(state.status)) return false;
    if (state.summarizing) return state.endedAt > 0 && now - state.endedAt > SUMMARY_WAIT_MS;
    return true;
}

export function hint(text) {
    const lines = String(text || "").split("\n").map(l => l.trim());
    const status = STATES.indexOf(lines[0]) >= 0 ? lines[0] : "idle";
    return { status, id: active(status) ? lines[1] || "" : "" };
}

export function clock(secs) {
    const s = Math.max(0, Math.floor(Number(secs) || 0));
    const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, r = s % 60;
    const two = n => String(n).padStart(2, "0");
    return h > 0 ? h + ":" + two(m) + ":" + two(r) : m + ":" + two(r);
}

export function length(secs) {
    const n = Math.round((Number(secs) || 0) / 60);
    if (!(Number(secs) > 0)) return "";
    if (n < 1) return "Under a minute";
    if (n < 60) return n + " min";
    return Math.floor(n / 60) + " h" + (n % 60 ? " " + (n % 60) + " min" : "");
}

export function speakers(segments) {
    const seen = new Map();
    for (const s of segments) {
        const k = s.who;
        const had = seen.get(k);
        if (had) had.lines++;
        else seen.set(k, { name: k, lines: 1, you: s.you });
    }
    return [...seen.values()].sort((a, b) => (b.you ? 1 : 0) - (a.you ? 1 : 0));
}

export function latest(segments) {
    for (let i = segments.length - 1; i >= 0; i--) if (segments[i].text.trim()) return segments[i];
    return null;
}

export function oneLine(text, max) {
    const t = String(text || "").replace(/\s+/g, " ").trim();
    const cap = max || 140;
    return t.length > cap ? t.slice(0, cap - 1).trimEnd() + "…" : t;
}

export function line(seg, opts) {
    if (!seg) return "";
    if (opts && opts.sharing) return "";
    const said = oneLine(seg.text, opts && opts.max);
    return said ? seg.who + ": " + said : "";
}

export function stageOf(meetingOn, dictating) {
    if (dictating) return "vox";
    return meetingOn ? "meet" : "";
}

export function parseList(text) {
    let raw;
    try { raw = JSON.parse(String(text || "")); } catch (e) { return null; }
    if (!Array.isArray(raw)) return null;
    return raw.filter(m => m && typeof m.id === "string" && m.id).map(m => ({
        id: m.id,
        title: String(m.title || "").trim(),
        startedAt: stamp(m.started_at),
        endedAt: stamp(m.ended_at),
        secs: Math.max(0, Number(m.duration_secs) || 0),
        status: String(m.status || ""),
        speakers: Math.max(0, Number(m.speaker_count) || 0),
        hasSummary: m.has_summary === true,
        url: typeof m.url === "string" ? m.url : ""
    }));
}

export function parseShow(text) {
    let raw;
    try { raw = JSON.parse(String(text || "")); } catch (e) { return null; }
    if (!raw || typeof raw !== "object" || !raw.metadata || typeof raw.metadata !== "object") return null;
    const m = raw.metadata;
    const segs = raw.transcript && Array.isArray(raw.transcript.segments) ? raw.transcript.segments : [];
    return {
        id: String(m.id || ""), title: String(m.title || "").trim(), startedAt: stamp(m.started_at),
        secs: Math.max(0, Number(m.duration_secs) || 0), status: String(m.status || ""),
        summary: summaryOf(m.summary), notes: String(raw.notes || "").trim(), segments: absorb([], segs)
    };
}

export function rowSub(m, words) {
    const w = words || {};
    const parts = [w.when || ""];
    if (m.speakers > 1) parts.push(m.speakers + " speakers");
    if (m.status === "interrupted") parts.push("Didn't finish");
    return parts.filter(x => x).join(" · ");
}

export function titleOr(m, fallback) {
    return m && m.title ? m.title : fallback;
}

const CALL_HOSTS = /^(?:[\w-]+\.)*(?:meet\.google\.com|zoom\.us|zoomgov\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|meet\.jit\.si|whereby\.com|gotomeeting\.com|meet\.goto\.com|chime\.aws|bluejeans\.com|around\.co|meet\.lync\.com|discord\.gg|app\.slack\.com)$/i;

export function callLink(text) {
    const found = String(text || "").match(/https:\/\/[^\s<>"'\\]+/gi) || [];
    for (const raw of found) {
        const url = raw.replace(/[),.;]+$/, "");
        const m = /^https:\/\/([^/:?#]+)/i.exec(url);
        if (m && CALL_HOSTS.test(m[1])) return url;
    }
    return "";
}

export function offerKey(e) {
    return e ? e.start + "|" + e.title : "";
}

export function offerFor(events, now, opts) {
    const o = opts || {};
    if (o.active || o.off) return null;
    const told = o.offered || {};
    for (const e of Array.isArray(events) ? events : []) {
        if (!e || e.allDay || !e.call) continue;
        if (e.start - now > OFFER_EARLY_MS || now - e.start > OFFER_LATE_MS || now >= e.end) continue;
        if (told[offerKey(e)]) continue;
        return { key: offerKey(e), title: String(e.title || ""), url: e.call, start: e.start, from: "calendar", private: !!e.private };
    }
    return null;
}

export function forgetOffers(offered, now) {
    const out = {};
    for (const k in offered || {}) if (now - Number(offered[k]) < FORGET_OFFERS_MS) out[k] = offered[k];
    return out;
}

export function parseSuggest(text) {
    const lines = String(text || "").split("\n");
    const head = lines.find(l => l.indexOf("Meeting detection in the daemon:") === 0) || "";
    const state = head.slice("Meeting detection in the daemon:".length).trim();
    const out = { known: head !== "", daemon: /^on\b/.test(state), enabled: head !== "" && state.indexOf("[meeting] enabled = false") < 0, prompt: null };
    for (const l of lines) {
        const m = /^would prompt: Record "(.*)"\? \((.+)\)\s*$/.exec(l.trim());
        if (m) { out.prompt = { title: m[1], app: m[2] }; break; }
    }
    return out;
}

export function viewRequest(text, now) {
    let r;
    try { r = JSON.parse(String(text || "")); } catch (e) { return null; }
    if (!r || typeof r !== "object") return null;
    const at = Number(r.requested_at);
    if (!Number.isFinite(at) || now - at > REQUEST_STALE_MS || at - now > REQUEST_STALE_MS) return null;
    const tab = ["transcript", "notes", "ask", "summary"].indexOf(r.tab) >= 0 ? r.tab : "";
    return { meeting: typeof r.meeting_id === "string" ? r.meeting_id : "", tab: r.ask_id ? "ask" : tab, open: r.open !== false, minimize: r.window === "minimize" };
}

export function viewState(visible, pid, nowSecs) {
    return JSON.stringify({ visible: !!visible, minimized: false, host: "kuwai", pid: Number(pid) || 0, updated_at: Math.floor(nowSecs) }) + "\n";
}

export function fileName(title, startedAt) {
    const d = new Date(Number(startedAt) || 0);
    const two = n => String(n).padStart(2, "0");
    const day = startedAt ? d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate()) : "";
    const safe = String(title || "Meeting").replace(/[\u0000-\u001f\u007f/\\]+/g, " ").replace(/^[.\s]+/, "").replace(/\s+/g, " ").trim().slice(0, 80) || "Meeting";
    return (day ? day + " " : "") + safe + ".md";
}

export function arm(armed, id) {
    if (armed === id) return { armed: "", fire: true };
    return { armed: id, fire: false };
}

export function trackWords(code, message) {
    if (code !== "track_not_transcribed") return "";
    const m = String(message || "");
    if (/microphone/i.test(m)) return "Your microphone has sound, but none of it is in the transcript yet.";
    if (/call|loopback/i.test(m)) return "The call has sound, but none of it is in the transcript yet.";
    return "One side has sound, but none of it is in the transcript yet.";
}

export function noticeWords(announces) {
    return announces
        ? "Voxtype announces the recording to the call. You're still responsible for getting consent where the law requires it."
        : "Some places require everyone on a call to agree to a recording. Voxtype doesn't tell them for you, so let them know.";
}
