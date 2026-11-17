// Dates and times in the user's locale: one place that knows the shapes the
// UI shows, so no surface types "dddd, MMMM d" (English order) again.
//
// Qt has no skeleton formatter (ICU's "weekday + day + month, no year"), but
// every locale gives its long date ("dddd, d. MMMM yyyy" in German,
// "yyyy年M月d日dddd" in Japanese, "dddd, d 'de' MMMM 'de' yyyy" in Spanish)
// and its short time ("h:mm Ap", "HH:mm", "H.mm", "Ap h:mm"). The shapes are
// cut from those: drop the year, shorten the names, drop the weekday. A field
// takes its own suffix with it (German "d.", Japanese "日", Korean "일"), and
// a separator left between two fields is the lighter of the two around it.
//
// The clock's hour cycle is Settings.clock24 (the user's choice wins); the
// locale still says where AM/PM goes and what it reads.
//
// Machine dates (file names, keys, anything parsed back) are not shapes
// here: they stay ISO (yyyy-MM-dd) where they are written.
//
// Plain ES for Qt's engine: no lookbehind, no spread, no named groups.
// Typed with JSDoc and checked by tsc (tsconfig.check.json); nothing compiled.
// @ts-check

/** A pattern field ("dddd", "MMM", "yyyy", "HH", "Ap"…) or literal text.
 *  @typedef {{ field: string, text: string }} Token */
/** @typedef {{ long: string, short: string, dayMonth: string, dayMonthYear: string, monthYear: string }} DateShapes */
/** @typedef {{ time: string, clock: string, clockSeconds: string }} TimeShapes */

const FIELD = /[dMyhHmszaApPt]/;
// Characters that separate two fields rather than belong to one.
const SEPARATOR = /[\s,،;/|\-–—]/;

/** Split a Qt date/time format into fields and literal text.
 *  @param {string} format @returns {Token[]} */
export function tokenize(format) {
    /** @type {Token[]} */
    const out = [];
    const s = String(format || "");
    let lit = "";
    const flush = () => { if (lit) { out.push({ field: "", text: lit }); lit = ""; } };
    let i = 0;
    while (i < s.length) {
        const c = s[i];
        if (c === "'") {
            // Quoted text; '' inside (or alone) is a quote mark.
            if (s[i + 1] === "'") { lit += "'"; i += 2; continue; }
            let j = i + 1;
            for (;;) {
                if (j >= s.length) break;
                if (s[j] === "'") {
                    if (s[j + 1] === "'") { lit += "'"; j += 2; continue; }
                    break;
                }
                lit += s[j];
                j++;
            }
            i = j + 1;
            continue;
        }
        if (FIELD.test(c)) {
            flush();
            let j = i;
            // AM/PM is "AP", "ap", "Ap" or "aP": two letters, one field.
            if ((c === "a" || c === "A") && (s[i + 1] === "p" || s[i + 1] === "P")) j = i + 2;
            else while (j < s.length && s[j] === c) j++;
            out.push({ field: s.slice(i, j), text: "" });
            i = j;
            continue;
        }
        lit += c;
        i++;
    }
    flush();
    return out;
}

/** A pattern from tokens; literal text is quoted where Qt would read it as a field.
 *  @param {Token[]} tokens @returns {string} */
export function build(tokens) {
    return tokens.map(t => {
        if (t.field) return t.field;
        return /[A-Za-z']/.test(t.text) ? "'" + t.text.replace(/'/g, "''") + "'" : t.text;
    }).join("");
}

/** How much of a literal is a field's own suffix ("." of "d.", "日"): the run
 *  before the first separator.
 *  @param {string} text @returns {number} */
function suffixLength(text) {
    let n = 0;
    while (n < text.length && !SEPARATOR.test(text[n])) n++;
    return n;
}

/** @param {string} text @returns {number} */
function weight(text) { return text.replace(/\s/g, "").length; }

/** Tokens without the fields `drop` matches, their suffixes, and the
 *  separators that no longer stand between two fields.
 *  @param {Token[]} tokens @param {(field: string) => boolean} drop @returns {Token[]} */
export function without(tokens, drop) {
    // 1. Each dropped field leaves a gap and takes its suffix ("d." → "").
    /** @type {{ field: string, text: string, gap: boolean }[]} */
    const items = [];
    for (let i = 0; i < tokens.length; i++) {
        const t = tokens[i];
        if (t.field && drop(t.field)) {
            items.push({ field: "", text: "", gap: true });
            const next = tokens[i + 1];
            if (next && !next.field) {
                const rest = next.text.slice(suffixLength(next.text));
                if (rest) items.push({ field: "", text: rest, gap: false });
                i++;
            }
            continue;
        }
        items.push({ field: t.field, text: t.text, gap: false });
    }
    // 2. Literals around a gap become one: the lighter separator ("MMMM d,
    //    yyyy" without d is "MMMM yyyy", not "MMMM, yyyy").
    /** @type {{ field: string, text: string, gap: boolean }[]} */
    const runs = [];
    for (const it of items) {
        const last = runs[runs.length - 1];
        if (!it.field && last && !last.field) {
            if (it.gap || last.gap) {
                if (it.text && (!last.text || weight(it.text) < weight(last.text))) last.text = it.text;
                last.gap = true;
            } else last.text += it.text;
            continue;
        }
        runs.push(it);
    }
    // 3. Nothing before the first field; after the last, only its own suffix
    //    (Hungarian "d." keeps its dot when the weekday after it goes).
    while (runs.length && !runs[0].field) runs.shift();
    const tail = runs[runs.length - 1];
    if (tail && !tail.field) {
        const n = tail.gap ? suffixLength(tail.text) : tail.text.length;
        if (n) tail.text = tail.text.slice(0, n);
        else runs.pop();
    }
    return runs.filter(t => t.field || t.text).map(t => ({ field: t.field, text: t.text }));
}

/** @param {Token[]} tokens @param {(field: string) => string} map @returns {Token[]} */
function mapFields(tokens, map) { return tokens.map(t => t.field ? { field: map(t.field), text: "" } : t); }

const isYear = (/** @type {string} */ f) => f[0] === "y";
const isWeekday = (/** @type {string} */ f) => f === "ddd" || f === "dddd";
const isDay = (/** @type {string} */ f) => f === "d" || f === "dd";
const shortNames = (/** @type {string} */ f) => f === "dddd" ? "ddd" : f === "MMMM" ? "MMM" : f;
/** @param {Token[]} t @param {string} c */
const has = (t, c) => t.some(x => x.field && x.field[0] === c);

/** English order, for a locale whose long date can't be cut (no day, month and weekday). */
export const FALLBACK_LONG = "dddd, MMMM d, yyyy";

/** Every date shape the UI shows, from the locale's long date format.
 *    long          Tuesday, November 17 · Dienstag, 17. November
 *    short         Tue, Nov 17 · Di., 17. Nov.
 *    dayMonth      Nov 17 · 17. Nov.
 *    dayMonthYear  Nov 17, 2026 · 17. Nov. 2026
 *    monthYear     November 2026 · 2026年11月
 *  @param {string} longFormat @returns {DateShapes} */
export function dateShapes(longFormat) {
    let all = tokenize(longFormat);
    if (!has(all, "d") || !has(all, "M") || !has(all, "y") || !all.some(t => t.field && isWeekday(t.field)))
        all = tokenize(FALLBACK_LONG);
    const long = without(all, isYear);
    const noWeekday = without(all, isWeekday);
    return {
        long: build(long),
        short: build(mapFields(long, shortNames)),
        dayMonth: build(mapFields(without(noWeekday, isYear), shortNames)),
        dayMonthYear: build(mapFields(noWeekday, shortNames)),
        monthYear: build(without(noWeekday, isDay)),
    };
}

/** Time shapes from the locale's short time format and the user's hour cycle.
 *    time          21:05 · 9:05 PM · 오후 9:05 (12 h, with the locale's marker)
 *    clock         21:05 · 9:05 (a big clock: no marker)
 *    clockSeconds  21:05:09 · 21.05.09 (the locale's separator)
 *  @param {string} shortTimeFormat @param {boolean} h24 @returns {TimeShapes} */
export function timeShapes(shortTimeFormat, h24) {
    let t = tokenize(shortTimeFormat);
    if (!has(t, "h") && !has(t, "H")) t = tokenize("HH:mm");
    if (!has(t, "m")) t = tokenize("HH:mm");
    const marker = (/** @type {string} */ f) => f[0] === "a" || f[0] === "A";
    const twelve = t.some(x => x.field && marker(x.field));
    let time;
    if (h24) {
        // The locale's own 24-hour digits ("H:mm" in Japanese); from a 12-hour
        // locale, two-digit hours.
        time = twelve ? mapFields(without(t, marker), f => f[0] === "h" || f[0] === "H" ? "HH" : f) : t;
    } else if (twelve) {
        time = t;
    } else {
        time = mapFields(t, f => f[0] === "H" || f[0] === "h" ? "h" : f).concat([{ field: "", text: " " }, { field: "Ap", text: "" }]);
    }
    const clock = without(time, marker);
    // Seconds after the minutes, with the separator between hours and minutes.
    let sep = ":";
    for (let i = 0; i + 2 < clock.length; i++) {
        if (clock[i].field && /^[hH]/.test(clock[i].field) && !clock[i + 1].field && clock[i + 2].field === "mm") { sep = clock[i + 1].text; break; }
    }
    /** @type {Token[]} */
    const seconds = [];
    for (const x of clock) {
        seconds.push(x);
        if (x.field === "mm") seconds.push({ field: "", text: sep }, { field: "ss", text: "" });
    }
    return { time: build(time), clock: build(clock), clockSeconds: build(seconds) };
}

/** The seven weekdays (0 = Sunday, as Date.getDay) from the locale's first.
 *  @param {number} firstDay @returns {number[]} */
export function weekOrder(firstDay) {
    const f = ((Math.floor(Number(firstDay) || 0) % 7) + 7) % 7;
    /** @type {number[]} */
    const out = [];
    for (let i = 0; i < 7; i++) out.push((f + i) % 7);
    return out;
}

/** Empty cells before the 1st in a grid whose rows start on `firstDay`.
 *  @param {number} weekdayOfFirst @param {number} firstDay @returns {number} */
export function leadDays(weekdayOfFirst, firstDay) {
    return ((weekdayOfFirst - weekOrder(firstDay)[0]) % 7 + 7) % 7;
}

/** Calendar days from `now` to `d` (−1 yesterday, 0 today, 1 tomorrow);
 *  counted on local midnights, so a 23- or 25-hour day is still one.
 *  @param {Date|number} d @param {Date|number} now @returns {number} */
export function dayOffset(d, now) {
    const a = new Date(d), b = new Date(now);
    const ua = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate());
    const ub = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate());
    return Math.round((ua - ub) / 86400000);
}

/** The words for the days next to today, in the user's language (Dates.qml
 *  passes Tr's; English when none are given).
 *  @typedef {{ today: string, yesterday: string, tomorrow: string }} DayWords */
/** @type {DayWords} */
export const ENGLISH_DAYS = { today: "Today", yesterday: "Yesterday", tomorrow: "Tomorrow" };

/** "Today", "Yesterday", "Tomorrow" (or the given words), or "" for any other day.
 *  @param {Date|number} d @param {Date|number} now @param {DayWords=} words @returns {string} */
export function relativeDay(d, now, words) {
    const w = words || ENGLISH_DAYS;
    const n = dayOffset(d, now);
    return n === 0 ? w.today : n === -1 ? w.yesterday : n === 1 ? w.tomorrow : "";
}

/** What the shell needs from a Qt Locale.
 *  @typedef {{ dateFormat: (f: number) => string, timeFormat: (f: number) => string,
 *              firstDayOfWeek: number, dayName: (day: number, f: number) => string,
 *              standaloneMonthName?: (month: number, f: number) => string }} LocaleLike */

/** A pattern with some fields written out as literal text before Qt sees it:
 *  the hour of a 12-hour clock without its marker (Qt writes "h" as 0–23
 *  unless the pattern has AM/PM: the old "h:mm" lock clock read 21:05), and
 *  a month named on its own (Russian "ноябрь 2026", not "ноября 2026").
 *  @param {string} pattern @param {Date} d @param {boolean} h24
 *  @param {((month: number) => string) | null} standaloneMonth @returns {string} */
export function resolve(pattern, d, h24, standaloneMonth) {
    const tokens = tokenize(pattern);
    const marker = tokens.some(t => t.field && (t.field[0] === "a" || t.field[0] === "A"));
    const day = tokens.some(t => t.field && isDay(t.field));
    return build(tokens.map(t => {
        if (!h24 && !marker && (t.field === "h" || t.field === "hh")) {
            const h = (d.getHours() + 11) % 12 + 1;
            return { field: "", text: t.field === "hh" && h < 10 ? "0" + h : String(h) };
        }
        if (!day && t.field === "MMMM" && standaloneMonth) {
            const name = standaloneMonth(d.getMonth());
            if (name) return { field: "", text: name };
        }
        return t;
    }));
}

/** A formatter bound to one locale and hour cycle. `render(date, pattern)`
 *  formats with that locale (in Qt: date.toLocaleString(locale, pattern));
 *  `formats` are Qt's Locale.LongFormat/ShortFormat/NarrowFormat values;
 *  `words` the relative days in the user's language (English if omitted).
 *  @param {LocaleLike} locale @param {boolean} h24
 *  @param {(d: Date, pattern: string) => string} render
 *  @param {{ long: number, short: number, narrow: number }} formats
 *  @param {DayWords=} words */
export function formatter(locale, h24, render, formats, words) {
    const ds = dateShapes(locale.dateFormat(formats.long));
    const ts = timeShapes(locale.timeFormat(formats.short), h24);
    const first = Number(locale.firstDayOfWeek) || 0;
    const standalone = typeof locale.standaloneMonthName === "function"
        ? (/** @type {number} */ m) => String(/** @type {Function} */ (locale.standaloneMonthName).call(locale, m, formats.long) || "")
        : null;
    /** @param {Date|number} d @param {string} p */
    const f = (d, p) => { const at = new Date(d); return render(at, resolve(p, at, h24, standalone)); };
    return {
        shapes: { date: ds, time: ts },
        firstDay: first,
        /** The big clock (lock, login, island, screensaver): no AM/PM. */
        clock: (/** @type {Date|number} */ d, /** @type {boolean=} */ seconds) => f(d, seconds ? ts.clockSeconds : ts.clock),
        /** A time in a sentence or a row: 21:05 · 9:05 PM. */
        time: (/** @type {Date|number} */ d) => f(d, ts.time),
        long: (/** @type {Date|number} */ d) => f(d, ds.long),
        short: (/** @type {Date|number} */ d) => f(d, ds.short),
        dayMonth: (/** @type {Date|number} */ d) => f(d, ds.dayMonth),
        dayMonthYear: (/** @type {Date|number} */ d) => f(d, ds.dayMonthYear),
        monthYear: (/** @type {Date|number} */ d) => f(d, ds.monthYear),
        weekday: (/** @type {Date|number} */ d, /** @type {boolean=} */ full) => f(d, full ? "dddd" : "ddd"),
        /** Within the coming week: "Tue 21:05". */
        weekdayTime: (/** @type {Date|number} */ d) => f(d, "ddd") + " " + f(d, ts.time),
        /** A day in a list: "Today", "Yesterday", "Tomorrow", else the short date. */
        day: (/** @type {Date|number} */ d, /** @type {Date|number} */ now) => relativeDay(d, now, words) || f(d, ds.short),
        /** A row's stamp: the time today, the day and month this year, else with the year. */
        stamp: (/** @type {Date|number} */ d, /** @type {Date|number} */ now) =>
            dayOffset(d, now) === 0 ? f(d, ts.time)
                : new Date(d).getFullYear() === new Date(now).getFullYear() ? f(d, ds.dayMonth) : f(d, ds.dayMonthYear),
        /** Month and year as separate runs in the locale's order, for a header
         *  that styles them apart: [{ text: "November", year: false }, { text: "2026", year: true }]. */
        monthYearParts: (/** @type {Date|number} */ d) => parts(tokenize(ds.monthYear)).map(p => ({ text: f(d, p.pattern), year: p.year })),
        /** Weekday names in grid order (from the locale's first day). */
        weekdayNames: (/** @type {boolean=} */ narrow) => weekOrder(first).map(i => locale.dayName(i, narrow ? formats.narrow : formats.short)),
        lead: (/** @type {Date|number} */ firstOfMonth) => leadDays(new Date(firstOfMonth).getDay(), first),
    };
}

/** A pattern's fields, each with its own suffix, as separate patterns.
 *  @param {Token[]} tokens @returns {{ pattern: string, year: boolean }[]} */
function parts(tokens) {
    /** @type {{ pattern: string, year: boolean }[]} */
    const out = [];
    for (let i = 0; i < tokens.length; i++) {
        const t = tokens[i];
        if (!t.field) continue;
        /** @type {Token[]} */
        const run = [t];
        const next = tokens[i + 1];
        if (next && !next.field) {
            const n = suffixLength(next.text);
            if (n) run.push({ field: "", text: next.text.slice(0, n) });
        }
        out.push({ pattern: build(run), year: isYear(t.field) });
    }
    return out;
}
