const HOUR = 3600000;

export function norm(s) {
    return String(s || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim();
}

export function sameMessage(a, b) {
    return !!a && !!b && a.app === b.app && norm(a.title) === norm(b.title) && norm(a.body) === norm(b.body) && norm(a.status) === norm(b.status);
}

export function repeats(items, fresh) {
    return (items || []).filter(i => i !== fresh && !i.popup && !i.discard && sameMessage(i, fresh));
}

export function threadKey(title) {
    return norm(title).slice(0, 80).toLowerCase();
}

export function t3Settled(items, t3, now) {
    if (!t3 || !t3.alive) return [];
    const listed = (t3.items || []).map(r => threadKey(r.title));
    const ended = (t3.rawItems || []).filter(r => r.status === "completed" || r.status === "failed");
    const everyEndedListed = (t3.rawFinished || 0) <= ended.length;
    const oldestListed = ended.reduce((m, r) => Math.min(m, Date.parse(r.at) || Infinity), Infinity);
    return (items || []).filter(i => i.app === "T3 Code" && !!i.status && !i.popup && !i.discard && !!norm(i.title)
        && now - i.time > HOUR / 30
        && listed.indexOf(threadKey(i.title)) < 0
        && (everyEndedListed || i.time >= oldestListed));
}

export function isSudoAsk(i) {
    return i.app === "Sudo" || /is asking for your password/i.test(norm(i.body));
}

export function expired(items, now, lastSeen, keepSeenHours) {
    return (items || []).filter(i => {
        if (i.popup || i.discard) return false;
        const age = now - i.time;
        const seen = i.time <= lastSeen;
        if (isSudoAsk(i)) return age > HOUR / 6;
        if (!seen) return false;
        if (Number(i.urgency) === 0) return age > HOUR;
        return keepSeenHours > 0 && age > keepSeenHours * HOUR;
    });
}

export function olderTwins(items) {
    const kept = [];
    const out = [];
    for (const i of [...(items || [])].sort((a, b) => b.time - a.time)) {
        if (i.popup || i.discard) continue;
        if (kept.some(k => sameMessage(k, i))) out.push(i);
        else kept.push(i);
    }
    return out;
}
