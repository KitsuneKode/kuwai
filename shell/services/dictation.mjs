const ENGINES = { parakeet: "Parakeet", whisper: "Whisper", moonshine: "Moonshine", sensevoice: "SenseVoice", paraformer: "Paraformer", dolphin: "Dolphin", omnilingual: "Omnilingual", cohere: "Cohere", gguf: "GGUF", openvino: "OpenVINO" };
const PROVIDERS = { local: "Ollama on this computer", groq: "Groq", groq2: "Groq (second key)", openrouter: "OpenRouter", opencode: "OpenCode", cerebras: "Cerebras" };
const SOURCES = [["seed", "built in", "built in"], ["auto", "learned by itself", "learned by itself"], ["user fix", "your fix", "your fixes"], ["accepted hint", "suggestion you accepted", "suggestions you accepted"], ["edit-watch", "from your edits", "from your edits"]];
const PILLS = [
    ["island", "Island", "In the island: status at the top, words in your field, or in the island where the field can't show them"],
    ["ticker", "Ticker", "The field shows the words; a one-line pill on the window's bottom edge shows the newest, or all of them where the field can't"],
    ["field", "Field", "The field shows the words; the pill at the bottom of the screen shows them only where the field can't"],
    ["words", "Words", "Every word in the pill at the bottom of the screen, the newest sliding in; for when words in the field are off"],
    ["status", "Status", "The field shows the words; the pill shows only the level and the time, and a caption on the window shows them where the field can't"]
];
const OUTCOMES = {
    ok: ["Delivered", "", "ok"],
    delivered: ["Delivered", "", "ok"],
    recovered: ["Kept for you", "Its window changed before it arrived; the bring-back key puts it where you are now", "warn"],
    clipboard_only: ["Copied, not typed", "The field didn't take it, so it went to the clipboard", "warn"],
    private_not_inserted: ["Not typed", "It was headed for a password field", "warn"],
    output_failed: ["Not typed", "Nothing reached the field", "bad"],
    failed: ["Not typed", "Nothing reached the field", "bad"],
    error: ["Not written out", "The engine stopped on it; restarting dictation may help", "bad"],
    no_speech: ["Nothing heard", "There was no speech in it", "quiet"],
    no_input: ["Silent microphone", "The microphone sent nothing; check the input in Sound", "warn"],
    too_short: ["Too short to keep", "A tap rather than a take", "quiet"],
    empty: ["No words", "It was heard, but no words came out", "quiet"],
    cancelled: ["Cancelled", "", "quiet"]
};

export function ms(n) {
    if (typeof n !== "number" || !isFinite(n) || n < 0) return "";
    if (n < 1000) return Math.round(n / 10) * 10 + " ms";
    return (Math.round(n / 100) / 10).toFixed(1) + " s";
}

export function ago(at, now) {
    if (typeof at !== "number" || !at) return "";
    const s = Math.max(0, Math.round((now - at) / 1000));
    if (s < 60) return "just now";
    if (s < 3600) return Math.round(s / 60) + " min ago";
    if (s < 86400) return Math.round(s / 3600) + " h ago";
    const d = Math.round(s / 86400);
    return d === 1 ? "yesterday" : d + " days ago";
}

export function engineName(id) {
    const s = String(id || "");
    return ENGINES[s] || (s ? s[0].toUpperCase() + s.slice(1) : "");
}

export function liveState(report, live) {
    const v = report && report.voxtype;
    if (!v || !v.installed) return "missing";
    const s = String(live || v.state || "");
    if (s === "streaming") return "recording";
    if (s === "recording" || s === "transcribing") return s;
    if (!v.running || s === "stopped") return "stopped";
    return "idle";
}

export function status(report, live) {
    const s = liveState(report, live);
    if (s === "missing") return { chip: "Not installed", detail: "The dictation engine isn't on this computer; the choices here appear once it is", tone: "off" };
    if (s === "stopped") return { chip: "Off", detail: "Dictation isn't running. It starts with your session; restarting it may help", tone: "bad" };
    if (s === "recording") return { chip: "Listening", detail: "Listening to a take now", tone: "busy" };
    if (s === "transcribing") return { chip: "Writing", detail: "Writing out what you said", tone: "busy" };
    return { chip: "Ready", detail: "Waiting for your key", tone: "ok" };
}

export function engine(v) {
    if (!v || !v.engine) return "";
    const name = engineName(v.engine);
    const b = String(v.backend || "");
    const how = b.match(/\(([^)]{1,24})\)/);
    if (v.gpu === true) return name + " on the graphics card" + (how ? " (" + how[1] + ")" : "");
    if (v.gpu === false) return name + " on the processor";
    return name;
}

export function model(v) {
    if (!v || !v.running) return "";
    const mins = Math.max(1, Math.round((v.unload_after || 0) / 60));
    if (v.model_state === "loaded") return v.unload_after > 0 ? "Ready in memory; set aside after " + mins + " min without a take" : "Ready in memory";
    if (v.model_state === "unloaded") return "Set aside to free memory; the next take loads it again";
    if (v.model_state === "on_demand") return "Loaded for each take, then set aside";
    return "";
}

export function lastTake(last, now) {
    if (!last || !OUTCOMES[last.outcome]) return { title: "", detail: "No take yet since dictation started", tone: "quiet" };
    const o = OUTCOMES[last.outcome];
    const when = ago(last.at, now);
    const size = (last.outcome === "ok" || last.outcome === "delivered") && last.chars > 0 ? (last.chars === 1 ? "1 character" : last.chars + " characters") : "";
    const head = [o[0] + (when ? " " + when : ""), size].filter(x => x).join(", ");
    const tail = [o[1], last.limit ? "It reached the longest take allowed" : ""].filter(x => x).join(". ");
    return { title: o[0], detail: head + (tail ? ". " + tail : ""), tone: o[2] };
}

export function providerName(id) {
    const s = String(id || "");
    return PROVIDERS[s] || (s ? s[0].toUpperCase() + s.slice(1) : "");
}

export function cleanup(sh) {
    const order = sh && Array.isArray(sh.order) ? sh.order : [];
    if (!order.length) return { chain: "Words arrive as they were heard", where: "No service tidies them", local: true, offline: false };
    const local = order.every(p => p === "local");
    const chain = order.map(providerName).join(", then ");
    const where = local ? "On this computer: your words never leave it"
        : order[0] === "local" ? "This computer first; online services only when it can't"
        : order.includes("local") ? "Online first; this computer when they can't"
        : "Online: your words are sent to these services to be tidied";
    return { chain: chain, where: where, local: local, offline: !!(sh && sh.offline) };
}

export function learning(l) {
    if (!l) return { rules: "", pending: "", vocab: "", waiting: 0 };
    const parts = SOURCES.map(([k, one, many]) => (l.by_source && l.by_source[k] > 0 ? l.by_source[k] + " " + (l.by_source[k] === 1 ? one : many) : "")).filter(x => x);
    const n = l.rules || 0;
    const rules = n === 0 ? "None yet: fixes you teach it show up here" : (n === 1 ? "1 correction" : n + " corrections") + (parts.length ? ": " + parts.join(", ") : "");
    const waiting = (l.pending_fixes || 0) + (l.pending_vocab || 0);
    const pending = waiting === 0 ? "Nothing waits for you" : waiting === 1 ? "1 suggestion waits for you" : waiting + " suggestions wait for you";
    const vocab = l.vocab > 0 ? (l.vocab === 1 ? "1 word" : l.vocab + " words") + " it listens out for" : "No words of your own yet";
    return { rules: rules, pending: pending, vocab: vocab, waiting: waiting };
}

export function speed(s) {
    if (!s || typeof s.p50 !== "number") return { value: "", detail: "Measured after a few dictations" };
    return { value: ms(s.p50), detail: "Half of takes within " + ms(s.p50) + ", nine in ten within " + ms(s.p90) + ", over the last " + s.n + " takes" };
}

export function delivered(d) {
    if (!d || typeof d.rate !== "number") return { value: "", detail: "Measured after a few dictations" };
    const pct = Math.round(d.rate * 100);
    return { value: pct + " %", detail: Math.round(d.rate * d.n) + " of the last " + d.n + " takes reached their field" };
}

export function options(values, current, label) {
    const list = values.slice();
    if (typeof current === "number" && list.indexOf(current) < 0) list.push(current);
    return list.sort((a, b) => a - b).map(n => ({ id: String(n), label: n === 0 ? "Off" : label(n) }));
}

export function keys(entries) {
    const rows = [];
    for (const e of Array.isArray(entries) ? entries : []) {
        if (!e || e.group !== "Dictation") continue;
        const row = rows.find(r => r.text === e.text);
        if (row) { if (e.keys) row.chords.push(e.keys); }
        else rows.push({ text: e.text, chords: e.keys ? [e.keys] : [] });
    }
    return rows;
}

export function pillChoices(allowed) {
    const ids = Array.isArray(allowed) ? allowed.map(String) : [];
    const known = PILLS.filter(p => ids.includes(p[0]));
    const more = ids.filter(id => id && !PILLS.some(p => p[0] === id)).map(id => [id, id[0].toUpperCase() + id.slice(1), ""]);
    return known.concat(more).map(p => ({ id: p[0], label: p[1], detail: p[2] }));
}

export function pillDetail(choices, current) {
    const c = (choices || []).find(x => x.id === current);
    return c ? c.detail : "";
}
