// The shell's words in the user's language: the pure half of Tr.qml.
//
// Quickshell 0.3.2 never installs a QTranslator (it builds a plain
// QQmlEngine), so qsTr() always returns its English source; and Qt's JS
// engine has no Intl, so no Intl.PluralRules either (docs/design/TRANSLATION.md).
// Instead: one JSON catalogue per language under shell/i18n/, keyed by the
// English text, which is also the fallback for any key a catalogue lacks.
//
//   { "Shut Down": "Ausschalten",
//     "{n} update": { "one": "{n} Aktualisierung", "other": "{n} Aktualisierungen" } }
//
// Placeholders are {name}; a value is inserted as plain text and never looked
// up itself (a window title or a notification's text is the sender's, not
// ours). Plural categories are CLDR's (zero one two few many other), chosen
// for integers by the language's rule below.
//
// Plain ES for Qt's engine: no lookbehind, no spread, no named groups.
// Typed with JSDoc and checked by tsc (tsconfig.check.json); nothing compiled.
// @ts-check

/** A catalogue entry: a translation, or one per plural category.
 *  @typedef {string | Object<string, string>} Entry */
/** @typedef {Object<string, Entry>} Catalogue */
/** @typedef {Object<string, string | number>} Args */

/** The categories a language uses, in CLDR's order.
 *  @param {string} lang @returns {string[]} */
export function categories(lang) {
    const f = family(lang);
    return f === "none" ? ["other"]
        : f === "slavic" || f === "polish" ? ["one", "few", "many", "other"]
        : f === "czech" ? ["one", "few", "other"]
        : f === "arabic" ? ["zero", "one", "two", "few", "many", "other"]
        : ["one", "other"];
}

/** Which integer plural rule a language follows (CLDR, integers only).
 *  @param {string} lang @returns {string} */
function family(lang) {
    const l = base(lang);
    if (["ja", "zh", "ko", "vi", "th", "id", "ms", "lo", "my", "km"].indexOf(l) >= 0) return "none";
    if (["ru", "uk", "be"].indexOf(l) >= 0) return "slavic";
    if (["pl"].indexOf(l) >= 0) return "polish";
    if (["cs", "sk"].indexOf(l) >= 0) return "czech";
    if (["ar"].indexOf(l) >= 0) return "arabic";
    // French and Brazilian Portuguese count 0 as singular.
    if (l === "fr" || String(lang).replace("-", "_") === "pt_BR") return "zero-one";
    return "one";
}

/** "de_DE" → "de". @param {string} lang @returns {string} */
function base(lang) { return String(lang || "").split(/[_-]/)[0].toLowerCase(); }

/** The plural category of a count in a language.
 *  @param {string} lang @param {number} count @returns {string} */
export function plural(lang, count) {
    const n = Math.abs(Math.floor(Number(count) || 0));
    const m10 = n % 10, m100 = n % 100;
    switch (family(lang)) {
    case "none": return "other";
    case "zero-one": return n <= 1 ? "one" : "other";
    case "slavic":
        return m10 === 1 && m100 !== 11 ? "one"
            : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? "few" : "many";
    case "polish":
        return n === 1 ? "one"
            : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? "few" : "many";
    case "czech": return n === 1 ? "one" : n >= 2 && n <= 4 ? "few" : "other";
    case "arabic":
        return n === 0 ? "zero" : n === 1 ? "one" : n === 2 ? "two"
            : m100 >= 3 && m100 <= 10 ? "few" : m100 >= 11 ? "many" : "other";
    default: return n === 1 ? "one" : "other";
    }
}

/** {name} → args.name, as text. An unknown {name} stays as written.
 *  @param {string} text @param {Args=} args @returns {string} */
export function fill(text, args) {
    const s = String(text);
    if (!args || s.indexOf("{") < 0) return s;
    let out = "";
    let i = 0;
    while (i < s.length) {
        const open = s.indexOf("{", i);
        if (open < 0) break;
        const close = s.indexOf("}", open + 1);
        if (close < 0) break;
        const name = s.slice(open + 1, close);
        out += s.slice(i, open);
        out += Object.prototype.hasOwnProperty.call(args, name) ? String(args[name]) : s.slice(open, close + 1);
        i = close + 1;
    }
    return out + s.slice(i);
}

/** The placeholders a text uses, sorted ("{n} of {total}" → ["n", "total"]).
 *  @param {string} text @returns {string[]} */
export function placeholders(text) {
    /** @type {string[]} */
    const out = [];
    const re = /\{([A-Za-z_][A-Za-z0-9_]*)\}/g;
    let m;
    while ((m = re.exec(String(text)))) if (out.indexOf(m[1]) < 0) out.push(m[1]);
    return out.sort();
}

/** The catalogues to try, best first, from Qt.locale().uiLanguages
 *  ("de-Latn-DE", "de-DE", "de-Latn", "de"; LANGUAGE=de:fr adds French after).
 *  Script subtags go; the list stops at English, the source language, so a
 *  user who puts English before German gets English.
 *  @param {string[]} uiLanguages @returns {string[]} */
export function candidates(uiLanguages) {
    /** @type {string[]} */
    const out = [];
    for (const tag of uiLanguages || []) {
        const parts = String(tag).split(/[-_.@]/).filter(p => p && !/^[A-Z][a-z]{3}$/.test(p));
        if (!parts.length) continue;
        const lang = parts[0].toLowerCase();
        if (lang === "en" || lang === "c" || lang === "posix") break;
        const region = parts.length > 1 && /^([A-Za-z]{2}|[0-9]{3})$/.test(parts[1]) ? parts[1].toUpperCase() : "";
        for (const c of region ? [lang + "_" + region, lang] : [lang]) if (out.indexOf(c) < 0) out.push(c);
    }
    return out;
}

/** The first candidate that has a catalogue, or "" for English.
 *  @param {string[]} wanted @param {string[]} available @returns {string} */
export function pick(wanted, available) {
    for (const c of wanted) if ((available || []).indexOf(c) >= 0) return c;
    return "";
}

/** A catalogue from a file's text: an object, or {} if it isn't one (a broken
 *  file falls back to English rather than taking the shell down).
 *  @param {string} text @returns {Catalogue} */
export function parse(text) {
    try {
        const v = JSON.parse(String(text || ""));
        return v && typeof v === "object" && !Array.isArray(v) ? v : {};
    } catch (e) {
        return {};
    }
}

/** A translated text with its placeholders filled; English when the
 *  catalogue lacks it (or holds something that isn't a string).
 *  @param {Catalogue} cat @param {string} text @param {Args=} args @returns {string} */
export function t(cat, text, args) {
    const v = cat && Object.prototype.hasOwnProperty.call(cat, text) ? cat[text] : null;
    return fill(typeof v === "string" && v ? v : text, args);
}

/** A count in a sentence: the form for `count` in `lang`, {n} filled with it.
 *  English (`one`, `other`) is the key and the fallback; a catalogue entry
 *  for `one` gives every category the language uses.
 *  @param {Catalogue} cat @param {string} lang @param {number} count
 *  @param {string} one @param {string} other @param {Args=} args @returns {string} */
export function n(cat, lang, count, one, other, args) {
    /** @type {Args} */
    const a = { n: count };
    if (args) for (const k in args) a[k] = args[k];
    const v = cat && Object.prototype.hasOwnProperty.call(cat, one) ? cat[one] : null;
    // A language with one form (Japanese) may give a plain string.
    if (lang && typeof v === "string" && v) return fill(v, a);
    if (lang && v && typeof v === "object") {
        const form = v[plural(lang, count)] || v.other;
        if (typeof form === "string" && form) return fill(form, a);
    }
    return fill(plural("en", count) === "one" ? one : other, a);
}

/** Pseudo-localisation for layout checks (KUWAI_PSEUDO=1): accented letters
 *  and ~40 % more length, in brackets so a clipped end shows. Placeholders
 *  stay as they are.
 *  @param {string} text @returns {string} */
export function pseudo(text) {
    const from = "aceinousyACEINOUSY";
    const to = "àçéîñöüšýÀÇÉÎÑÖÜŠÝ";
    let out = "";
    let depth = 0;
    let letters = 0;
    for (const c of String(text)) {
        if (c === "{") depth++;
        if (c === "}") depth = Math.max(0, depth - 1);
        const k = depth ? -1 : from.indexOf(c);
        out += k >= 0 ? to[k] : c;
        if (!depth && /[A-Za-z]/.test(c)) letters++;
    }
    let pad = "";
    for (let i = 0; i < Math.ceil(letters * 0.4); i++) pad += "~";
    return "[" + out + (pad ? " " + pad : "") + "]";
}
