// One-time codes in notifications: which number is the code, if any.
//
// The first detector asked two loose questions (does the text mention
// code / sign in / security / confirm anywhere? is there a 6–8 digit number
// anywhere?) and called the pair a code. On a developer's desktop that is
// most of GitHub: "chore/dead-code-and-size-20261117" has a "code" and eight
// digits; a job advert has "sign in" and an id in its link (8 of 54 stored
// notifications, every one wrong, 2026-11-17). The notch then showed a date
// in the big code face with a Copy button.
//
// The rule now is the one a person uses: a number is a code when the words
// right beside it say so.
//
//   "Your verification code is 482913"      a code phrase, then the number
//   "OTP: 482 913" · "PIN 4821"             the same, tight
//   "482913 is your Google code"            the number, then "is your … code"
//   "Use 77F3K9QA to sign in"               use / enter X to … sign in
//   "G-482913 is your verification code"    a sender's prefix is dropped
//
// and never: part of a link or an address, a longer number, a version, an
// amount, a time, a year, a date (20261117), a branch or file name, "exit
// code 137", "error code 4012", "T3 Code", "zip code 560001".
//
// English phrases only for now; a code in another language is shown as the
// plain notification it is (safe: nothing is hidden wrongly, nothing copied).
//
// Plain ES for Qt's engine: no lookbehind, no spread, no named groups.
// Typed with JSDoc and checked by tsc (tsconfig.check.json, CI): Quickshell
// loads .mjs as it is, so types live in comments and nothing is compiled.
// @ts-check

/** What a notification says. @typedef {{ title?: string, body?: string, full?: string }} Notice */
/** A token shaped like a code. @typedef {{ code: string, at: number, end: number, alnum: boolean }} Candidate */

const STRONG = "(?:otp|one[- ]?time (?:pass(?:word|code)|code|pin)|pass ?code|"
    + "(?:verification|security|log[- ]?in|sign[- ]?in|authentication|auth|authori[sz]ation|confirmation|access|"
    + "2fa|two[- ]factor|two[- ]step|recovery|reset|activation|pairing) (?:code|pin))";

// "<word> code" that is not a code to type.
const NOT_CODES = /^(?:error|exit|status|zip|postal|post|area|country|promo|discount|coupon|voucher|referral|invite|source|qr|bar|http|response|return|result|product|tracking|colou?r|dial|dead|clean|legacy|t3|claude|vs|studio|roo|kilo|open|no|low)$/i;

const STRONG_BEFORE = new RegExp("(?:^|[^\\w-])" + STRONG + "s?\\b([^\\d]{0,45})$", "i");
const STRONG_ANY = new RegExp("(?:^|[^\\w-])" + STRONG + "s?\\b", "i");
const WEAK_BEFORE = /(?:^|[^\w-])(?:([A-Za-z0-9]+) +)?(?:code|pin)\s*(?:is)?\s*[:=–—-]?\s*$/i;
// "… one-time password for the transfer of Rs 5,000.00 is 482913": the phrase
// earlier in the same sentence (figures may come between), and the number
// handed over by "is" or a colon.
const STRONG_EARLIER = new RegExp("(?:^|[^\\w-])" + STRONG + "s?\\b(.{0,80})$", "i");
const HANDED_OVER = /(?:\bis|:)\s*$/i;
const VERB_BEFORE = /\b(?:verify|verification|sign[- ]?in|log[- ]?in|authenticate|confirm)\b[^\d!?]{0,50}\b(?:use|enter|type)\s*:?\s*$/i;
const ASK_BEFORE = /\b(?:use|enter|type)\s*:?\s*$/i;
const IS_YOUR_AFTER = /^\s+(?:is|as)\s+(?:your|the)\b[^\d]{0,40}?\b(?:code|otp|pin|passcode|password)\b/i;
const PURPOSE_AFTER = /^[^\d!?]{0,45}?\b(?:code|otp|pin|passcode|verify|verification|sign[- ]?in|log[- ]?in|confirm)/i;

// What a notification says, without what can't hold a code to type: link
// targets (the label stays), bare links, addresses. One line, single spaces.
/** @param {unknown} text @returns {string} */
export function clean(text) {
    return String(text || "")
        .replace(/\[([^\]]*)\]\(<?[^)\s>]*>?\)/g, "$1")
        .replace(/<?\bhttps?:\/\/[^\s>)\]]+>?/g, " ")
        .replace(/\b[\w.+-]+@[\w-]+\.[\w.-]+\b/g, " ")
        .replace(/\s+/g, " ")
        .trim();
}

/** @param {string} d */
function isDate(d) {            // 20261117
    if (d.length !== 8) return false;
    const y = +d.slice(0, 4), m = +d.slice(4, 6), day = +d.slice(6);
    return y >= 1990 && y <= 2099 && m >= 1 && m <= 12 && day >= 1 && day <= 31;
}

// Every token shaped like a code, standing on its own: 4–8 digits (also as
// "123 456" / "1234-5678", or behind a sender's "G-"), or 6–8 capitals and
// digits mixed. { code, at, end, alnum } in reading order.
/** @param {unknown} text @returns {Candidate[]} */
export function candidates(text) {
    const t = String(text || "");
    /** @type {Candidate[]} */
    const out = [];
    // Order matters: a mixed token before a run of digits ("1234ABCD" is one
    // token, not "1234" with letters stuck to it).
    const shape = /[A-Z]{1,3}-\d{4,8}|[A-Z0-9]{6,8}|\d{3}[- ]\d{3}|\d{4}[- ]\d{4}|\d{4,8}/g;
    let m;
    while ((m = shape.exec(t)) !== null) {
        const raw = m[0], i = m.index, j = i + raw.length;
        const l = i > 0 ? t[i - 1] : "", ll = i > 1 ? t[i - 2] : "";
        const r = j < t.length ? t[j] : "", rr = j + 1 < t.length ? t[j + 1] : "";
        // Part of something longer: a word, an amount, a version, a time, a
        // path, a branch name, a phone number.
        if (/[\w#$₹€£+\/@~]/.test(l)) continue;
        if (/[.,:]/.test(l) && /\d/.test(ll)) continue;
        if (l === "-" && /\w/.test(ll)) continue;
        if (/[\w%@]/.test(r)) continue;
        if (/[.,:\/_-]/.test(r) && /\w/.test(rr)) continue;
        const prefixed = /^[A-Z]{1,3}-/.test(raw);
        const digits = /^[\d -]+$/.test(raw) || prefixed;
        const code = digits ? raw.replace(/^[A-Z]{1,3}-/, "").replace(/[- ]/g, "") : raw;
        if (digits) {
            if (/^(19|20)\d\d$/.test(code) || isDate(code)) continue;
        } else if (!/\d/.test(code) || !/[A-Z]/.test(code)) continue;
        out.push({ code: code, at: i, end: j, alnum: !digits });
    }
    return out;
}

/** @param {Notice | null | undefined} item */
function textOf(item) {
    if (!item) return "";
    return clean([item.title, item.body, item.full].filter(x => x).join("\n"));
}

// The one published format (WICG "Origin-bound one-time codes delivered via
// SMS", by Apple and Google; what Chrome's WebOTP and Safari's autofill
// read): the message's last line is "@example.com #123456". A sender that
// writes it has said in so many words which token is the code and whose it
// is, so it is read before any phrase. { host, code } or null.
/** @param {unknown} text @returns {{ host: string, code: string } | null} */
export function originBound(text) {
    const m = /(?:^|\n)[ \t]*@([a-z0-9-]+(?:\.[a-z0-9-]+)+)[ \t]+#([A-Za-z0-9]{4,10})(?:[ \t]+@\S+)?\s*$/i.exec(String(text || ""));
    return m ? { host: m[1].toLowerCase(), code: m[2] } : null;
}

// The code, or "": the sender's own marking first, else the first candidate
// whose neighbours call it one.
/** @param {Notice | string | null | undefined} item @returns {string} */
export function otpOf(item) {
    const raw = typeof item === "string" ? item : !item ? "" : [item.body, item.full].filter(x => x).join("\n");
    const bound = originBound(raw);
    if (bound) return bound.code;
    const t = typeof item === "string" ? clean(item) : textOf(item);
    if (t === "") return "";
    const list = candidates(t);
    for (let k = 0; k < list.length; k++) {
        const c = list[k];
        const before = t.slice(Math.max(0, c.at - 90), c.at), after = t.slice(c.end, c.end + 70);
        const strong = STRONG_BEFORE.exec(before);
        if (strong) {
            const gap = strong[1];
            // Not across a sentence ("Your security code changed. Order 554321 …"),
            // and a word-like code only right after "is" or ":".
            const sameSentence = !/[.!?]\s+\S/.test(gap);
            if (sameSentence && (!c.alnum || /(?:\bis|:)\s*$/i.test(gap))) return c.code;
        }
        const earlier = STRONG_EARLIER.exec(before);
        if (earlier && HANDED_OVER.test(before) && !/[.!?]\s+\S/.test(earlier[1])) return c.code;
        const weak = WEAK_BEFORE.exec(before);
        if (weak && !(weak[1] && NOT_CODES.test(weak[1]))
            && (!c.alnum || /(?:\bis|:)\s*$/i.test(before))) return c.code;
        if (!c.alnum && VERB_BEFORE.test(before)) return c.code;
        if (IS_YOUR_AFTER.test(after)) return c.code;
        if (ASK_BEFORE.test(before) && PURPOSE_AFTER.test(after)) return c.code;
    }
    return "";
}

// Does the text talk about a code at all (and not about exit codes, zip codes
// or an app called Code)?
/** @param {unknown} text @returns {boolean} */
export function mentionsCode(text) {
    const t = clean(text);
    if (STRONG_ANY.test(t)) return true;
    const word = /(?:^|[^\w-])(?:([A-Za-z0-9]+) +)?(?:code|pin)\b(?!-)/gi;
    let m;
    while ((m = word.exec(t)) !== null) if (!(m[1] && NOT_CODES.test(m[1]))) return true;
    return false;
}

// The lock screen's question, more careful than the notch's: could this hold
// a code? It hides on "talks about a code and has a number that could be
// one", without asking that they sit together. Still never a link, a date, a
// branch name or a version.
/** @param {Notice | string | null | undefined} item @returns {boolean} */
export function otpLikely(item) {
    const t = typeof item === "string" ? clean(item) : textOf(item);
    if (t === "" || !mentionsCode(t)) return false;
    return candidates(t).some(c => !c.alnum);
}

// A line that itself shows something code-shaped (the lock hides such a title).
/** @param {unknown} text @returns {boolean} */
export function codeShaped(text) { return candidates(clean(text)).length > 0; }

/**
 * Never written to history: a code the card would show, a code anywhere in
 * the conversation it carries, or a body that is nothing but a code ("Sign
 * in" / "482913"). Stricter than what the card does with it.
 * @param {{ title?: string, body?: string, full?: string, thread?: unknown }} item
 * @returns {boolean}
 */
export function secretForHistory(item) {
    if (!item) return false;
    if (otpOf(item) !== "" || otpLikely(item)) return true;
    const body = clean(String(item.body || "")).trim();
    if (/^[A-Z0-9-]{4,10}$/i.test(body) && (body.match(/\d/g) || []).length >= 4) return true;
    const thread = item.thread ? (typeof item.thread === "string" ? item.thread : JSON.stringify(item.thread)) : "";
    return thread !== "" && (otpLikely(thread) || otpOf({ body: thread }) !== "");
}
