const IMAGE = /\.(jpe?g|png|webp|gif|bmp|avif|mp4|webm|mkv|mov)$/i;
const LEVEL = /^\s*(?:(?:volume|brightness|mic(?:rophone)?)\s*:?\s*)?(?:\d{1,3}\s*%|muted|unmuted)\s*$|^\s*(?:volume|brightness|muted|unmuted)\s*$/i;
const STATUS_SENDER = /^$|wall|theme|alert|notify|swww|awww|waypaper|variety|notify-send/i;
const FAILURE = /\b(fail(ed|ure)?|error|not (found|installed)|unavailable|couldn'?t|can'?t)\b/i;

function text(v) { return String(v || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim(); }
function hint(n, k) { return n && n.hints ? n.hints[k] : undefined; }
function actionless(n) { return !n || !(n.actions || []).some(a => a && (a.identifier || a.id) && (a.identifier || a.id) !== "default"); }

export function statusNotice(n) {
    const app = text(n.app || n.appName);
    const title = text(n.summary || n.title);
    if (/live wallpaper/i.test(app)) return true;
    if (actionless(n) && /^wallpaper set for/i.test(title)) return true;
    if (actionless(n) && IMAGE.test(title) && !/\s/.test(title) && STATUS_SENDER.test(app)) return true;
    if (actionless(n) && LEVEL.test(title)) return true;
    const sync = String(hint(n, "x-canonical-private-synchronous") || hint(n, "x-dunst-stack-tag") || "");
    if (/^(brightness|volume|audio|sink|mic)$/i.test(sync)) return true;
    return hint(n, "value") !== undefined && actionless(n);
}

export function kittyCommandDone(n) {
    const app = text(n.app || n.appName).toLowerCase();
    const title = text(n.summary || n.title).toLowerCase();
    return (app === "kitty" || title === "kitty") && /^command\b/i.test(text(n.body));
}

export function fromFocused(n, focused) {
    if (!focused || !actionless(n) || Number(n.urgency) === 2) return false;
    const names = [focused.appId, focused.class].map(s => String(s || "").toLowerCase().replace(/\.desktop$/, "")).filter(s => s);
    const from = [n.desktopEntry, n.app || n.appName].map(s => String(s || "").toLowerCase().replace(/\.desktop$/, "")).filter(s => s);
    if (!from.some(f => names.some(x => x === f || x.endsWith("." + f) || f.endsWith("." + x)))) return false;
    const title = text(n.summary || n.title).toLowerCase();
    const window = String(focused.title || "").toLowerCase();
    return !title || window.includes(title) || kittyCommandDone(n);
}

export function authAsk(i) {
    return i.app === "Sudo" || /is asking (for your password|you to log in)|is waiting for a yes or a no/i.test(text(i.body));
}

export function triage(n, focused) {
    if (Number(n.urgency) === 2) return "keep";
    if (statusNotice(n)) return FAILURE.test(text(n.summary || n.title) + " " + text(n.body)) ? "toast" : "drop";
    if (fromFocused(n, focused)) return "drop";
    if (n.transient) return "toast";
    return "keep";
}
