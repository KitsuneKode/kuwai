// The locale half of shell/config/dates.mjs, in Qt's own engine: run by
// tests/shell/test_dates_locale.py under several LC_ALL values with the
// offscreen platform. Prints one JSON line (DATES_RESULT) and quits.
import QtQuick
import "../../shell/config/dates.mjs" as D

QtObject {
    Component.onCompleted: {
        const loc = Qt.locale();
        const formats = { long: Locale.LongFormat, short: Locale.ShortFormat, narrow: Locale.NarrowFormat };
        const out = { locale: loc.name };
        for (const h24 of [true, false]) {
            const f = D.formatter(loc, h24, (d, p) => d.toLocaleString(loc, p), formats);
            const at = new Date(2026, 10, 17, 21, 5, 9);     // Tuesday 17 November 2026, 21:05:09
            const k = h24 ? "h24" : "h12";
            out[k] = {
                clock: f.clock(at), clockSeconds: f.clock(at, true), time: f.time(at),
                long: f.long(at), short: f.short(at), dayMonth: f.dayMonth(at),
                dayMonthYear: f.dayMonthYear(at), monthYear: f.monthYear(at),
                monthYearParts: f.monthYearParts(at), weekdayTime: f.weekdayTime(at),
                firstDay: f.firstDay, weekdayNames: f.weekdayNames(), lead: f.lead(new Date(2026, 10, 1)),
                today: f.day(at, at), stampOld: f.stamp(new Date(2025, 0, 2), at),
            };
        }
        console.warn("DATES_RESULT " + JSON.stringify(out));
        Qt.quit();
    }
}
