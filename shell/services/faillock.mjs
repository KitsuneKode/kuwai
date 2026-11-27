export const DEFAULTS = { deny: 3, failInterval: 900, unlockTime: 600 };

export function parseConf(text) {
    const conf = Object.assign({}, DEFAULTS);
    const get = k => {
        const m = String(text || "").match(new RegExp("^\\s*" + k + "\\s*=\\s*(\\d+)", "m"));
        return m ? parseInt(m[1], 10) : -1;
    };
    if (get("deny") > 0) conf.deny = get("deny");
    if (get("fail_interval") > 0) conf.failInterval = get("fail_interval");
    if (get("unlock_time") >= 0) conf.unlockTime = get("unlock_time");
    return conf;
}

export function tally(text, now, conf) {
    let fails = 0, last = 0;
    for (const l of String(text || "").split("\n")) {
        const m = l.match(/^(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d)\s+\S+(?:\s+\S+)?\s+V\s*$/);
        if (!m) continue;
        const at = new Date(m[1] + "T" + m[2]).getTime();
        if (now - at <= conf.failInterval * 1000) { fails++; last = Math.max(last, at); }
    }
    const lockedUntil = fails >= conf.deny && conf.unlockTime > 0 ? last + conf.unlockTime * 1000 : 0;
    return { fails, lockedUntil };
}

export function mmss(s) { return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }

export function missWords(fails, conf) {
    const left = Math.max(0, conf.deny - fails);
    if (left <= 0) return "Incorrect password";
    if (left === 1) {
        const mins = Math.round(conf.unlockTime / 60);
        return mins > 0 ? `Incorrect password · last try before a ${mins}-minute wait` : "Incorrect password · 1 try left";
    }
    return `Incorrect password · ${left} tries left`;
}

export function lockedWords(secondsLeft) {
    return `Too many tries · try again in ${mmss(secondsLeft)}`;
}
