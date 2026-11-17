// Dates and times the way the user's locale writes them (dates.mjs cuts the
// shapes from the locale's own formats; Settings.clock24 picks the hour
// cycle). Every surface formats through here: never a hand-written order.
//
//   Dates.clock(now)          21:05            the big clocks (no AM/PM)
//   Dates.time(at)            21:05 · 9:05 PM  a time in a row or a sentence
//   Dates.longDate(now)       Tuesday, November 17 · Dienstag, 17. November
//   Dates.shortDate(now)       Tue, Nov 17 · Di., 17. Nov.
//   Dates.dayMonth(at)        Nov 17 · 17. Nov.
//   Dates.monthYear(month)    November 2026 · 2026年11月
//   Dates.weekdayTime(at)     Tue 21:05
//   Dates.day(at, now)        Today · Yesterday · Tomorrow · Tue, Nov 17 (Heute… via Tr)
//   Dates.stamp(at, now)      21:05 today, Nov 17 this year, else Nov 17, 2025
//   Dates.weekdayNames()      Mon … Sun, from the locale's first day
//   Dates.lead(firstOfMonth)  empty cells before the 1st in a month grid
//
// Machine dates (file names, keys, anything parsed back) stay ISO where they
// are written (yyyy-MM-dd), not here.
pragma Singleton

import QtQuick
import Quickshell
import "dates.mjs" as D

Singleton {
    id: root
    readonly property var locale: Qt.locale()
    // The relative days in the user's language (Tr; English without a catalogue).
    readonly property var words: ({ today: Tr.t("Today"), yesterday: Tr.t("Yesterday"), tomorrow: Tr.t("Tomorrow") })
    readonly property var f: D.formatter(locale, Settings.clock24, (d, p) => d.toLocaleString(locale, p),
                                         { long: Locale.LongFormat, short: Locale.ShortFormat, narrow: Locale.NarrowFormat }, words)
    // 0 = Sunday … 6 = Saturday, as Date.getDay().
    readonly property int firstDay: f.firstDay

    function clock(d, seconds) { return f.clock(d, !!seconds); }
    function time(d) { return f.time(d); }
    function longDate(d) { return f.long(d); }
    function shortDate(d) { return f.short(d); }
    function dayMonth(d) { return f.dayMonth(d); }
    function dayMonthYear(d) { return f.dayMonthYear(d); }
    function monthYear(d) { return f.monthYear(d); }
    function monthYearParts(d) { return f.monthYearParts(d); }
    function weekday(d, full) { return f.weekday(d, !!full); }
    function weekdayTime(d) { return f.weekdayTime(d); }
    function day(d, now) { return f.day(d, now || new Date()); }
    function stamp(d, now) { return f.stamp(d, now || new Date()); }
    function weekdayNames(narrow) { return f.weekdayNames(!!narrow); }
    function lead(firstOfMonth) { return f.lead(firstOfMonth); }
    // Weekdays (0 = Sunday) in grid order and whether each is a working day,
    // by the locale (a Friday–Saturday weekend in Egypt).
    function weekOrder() { return D.weekOrder(firstDay); }
    function isWeekend(day) { return (locale.weekDays || [1, 2, 3, 4, 5]).indexOf(day) < 0; }
    function relativeDay(d, now) { return D.relativeDay(d, now || new Date(), words); }
    function dayOffset(d, now) { return D.dayOffset(d, now || new Date()); }
}
