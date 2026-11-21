// The calendar, grown out of the island's clock: a month at a time, today as
// a white disc (Apple's), the selected day ringed. Keys: ←→ day, ↑↓ week,
// PgUp/PgDn (or [ ]) month, T today, Esc closes.
//
//   October 2026                          ‹  ›
//   Mon Tue Wed Thu Fri Sat Sun        (the locale's order and first day)
//    28  29  30   1   2   3   4
//   …
//   Thursday, October 29 · Week 44     (dates through config/Dates)
import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

FocusScope {
    id: cal
    focus: true

    property date today: new Date()
    // The island's clock lands here (IslandBar's flyer); IslandBar keeps it ticking.
    property date now: new Date()
    // On the minute, while it shows (the clock and what's "now" froze while open).
    Timer {
        running: cal.visible
        interval: 60000 - (Date.now() % 60000) + 50
        onTriggered: { cal.now = new Date(); interval = 60000 - (Date.now() % 60000) + 50; restart(); }
    }
    readonly property Item clockItem: calClock
    property bool clockHidden: false
    property date selected: today
    // The month shown: its first day.
    property date month: new Date(today.getFullYear(), today.getMonth(), 1)

    readonly property int cell: Theme.sp(40)
    implicitWidth: cell * 7 + 44
    // As tall as it needs, up to what the island gives; past that (a large
    // Text size, a long day) it scrolls, with the shell's fade.
    readonly property real ceiling: Math.min(Theme.panelMaxH, Theme.screenSize(Screen, "height", 1080) - 64)
    implicitHeight: Math.min(col.implicitHeight + 40, ceiling)

    function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate(); }
    function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n); }
    function select(d) {
        selected = d;
        if (d.getMonth() !== month.getMonth() || d.getFullYear() !== month.getFullYear())
            month = new Date(d.getFullYear(), d.getMonth(), 1);
    }
    function shiftMonth(n) {
        month = new Date(month.getFullYear(), month.getMonth() + n, 1);
        const last = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
        selected = new Date(month.getFullYear(), month.getMonth(), Math.min(selected.getDate(), last));
    }
    // ISO week number.
    function week(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - y0) / 86400000 + 1) / 7);
    }
    // The 42 days on the grid, from the locale's first day of the week.
    readonly property var days: {
        const lead = Dates.lead(month);
        const start = addDays(month, -lead);
        const out = [];
        for (let i = 0; i < 42; i++) out.push(addDays(start, i));
        return out;
    }

    Keys.onPressed: event => {
        const k = event.key;
        if (k === Qt.Key_Left) select(addDays(selected, -1));
        else if (k === Qt.Key_Right) select(addDays(selected, 1));
        else if (k === Qt.Key_Up) select(addDays(selected, -7));
        else if (k === Qt.Key_Down) select(addDays(selected, 7));
        else if (k === Qt.Key_PageUp || k === Qt.Key_BracketLeft) shiftMonth(-1);
        else if (k === Qt.Key_PageDown || k === Qt.Key_BracketRight) shiftMonth(1);
        else if (k === Qt.Key_T) select(today);
        else return;
        event.accepted = true;
    }

    ScrollFade { flickable: calFlick }
    ScrollHint { flickable: calFlick; anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 4 } }
    Flickable {
        id: calFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 40
        interactive: contentHeight > height + 1
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            x: 22; y: 20
            spacing: 10

            Row {
                spacing: 10
                IslandClock {
                    id: calClock
                    opacity: cal.clockHidden ? 0 : 1   // not visible: the Row would close up under the flying clock
                    now: cal.now; size: Theme.tClock
                    rounded: false; weight: Theme.wMedium
                    color: Qt.rgba(1, 0.98, 0.95, 0.95)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Dates.longDate(cal.now)
                    size: Theme.tHeadline; weight: Theme.wMedium
                    color: Theme.textTertiary
                }
            }

            Item {
                width: cal.cell * 7
                height: Theme.sp(30)
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7
                    // Month and year in the locale's order (2026年 11月 in Japanese);
                    // the month carries the weight, the year recedes.
                    Repeater {
                        model: Dates.monthYearParts(cal.month)
                        Label {
                            required property var modelData
                            text: modelData.text; size: 20
                            weight: modelData.year ? Theme.wRegular : Theme.wSemibold
                            color: modelData.year ? Theme.textTertiary : Theme.textPrimary
                        }
                    }
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Repeater {
                        model: [{ g: "\u{f0141}", d: -1 }, { g: "\u{f0142}", d: 1 }]
                        Rectangle {
                            id: nav
                            required property var modelData
                            width: 28; height: 28; radius: 14
                            color: navArea.containsMouse ? Theme.pillHover : "transparent"
                            scale: navArea.pressed ? 0.94 : 1
                            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                            Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                            Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: nav.modelData.g; font.family: Theme.fontGlyph; font.pixelSize: Theme.glyphS; color: Theme.textSecondary }
                            MouseArea { id: navArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cal.shiftMonth(nav.modelData.d) }
                            Accessible.role: Accessible.Button
                            Accessible.name: nav.modelData.d < 0 ? "Previous month" : "Next month"
                            Accessible.onPressAction: cal.shiftMonth(nav.modelData.d)
                        }
                    }
                }
            }

            Row {
                Repeater {
                    model: Dates.weekOrder()
                    Label {
                        required property int modelData
                        required property int index
                        width: cal.cell
                        horizontalAlignment: Text.AlignHCenter
                        text: Dates.weekdayNames()[index]
                        size: 11
                        weight: Theme.wMedium
                        color: Dates.isWeekend(modelData) ? Theme.textTertiary : Theme.textSecondary
                    }
                }
            }

            Grid {
                columns: 7
                Repeater {
                    model: cal.days
                    Item {
                        id: day
                        required property var modelData
                        readonly property bool inMonth: modelData.getMonth() === cal.month.getMonth()
                        readonly property bool isToday: cal.sameDay(modelData, cal.today)
                        readonly property bool isSel: cal.sameDay(modelData, cal.selected)
                        width: cal.cell; height: cal.cell - 6
                        Rectangle {
                            anchors.centerIn: parent
                            width: Theme.sp(32); height: width; radius: width / 2
                            color: day.isToday ? "white" : dayArea.containsMouse ? Theme.pill : "transparent"
                            border.width: day.isSel && !day.isToday ? 1.5 : 0
                            border.color: Qt.rgba(1, 1, 1, 0.55)
                            Behavior on color { ColorAnimation { duration: Theme.colorMs } }
                        }
                        Label {
                            anchors.centerIn: parent
                            text: day.modelData.getDate()
                            rounded: true
                            size: 14
                            weight: day.isToday ? Theme.wSemibold : Theme.wRegular
                            color: day.isToday ? Theme.inkOnLight : !day.inMonth ? Theme.textTertiary : Theme.textPrimary   // another month's days: tertiary (at 38 % white they read 3.6:1)
                            font.features: ({ "tnum": 1 })
                        }
                        // Something on that day: a small dot under the number.
                        Rectangle {
                            visible: Calendar.events.length > 0 && Calendar.eventsOn(day.modelData).length > 0
                            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
                            width: 4; height: 4; radius: 2
                            color: day.inMonth ? Theme.textSecondary : Qt.rgba(1, 1, 1, 0.25)
                        }
                        MouseArea { id: dayArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cal.select(day.modelData) }
                        Accessible.role: Accessible.Cell
                        Accessible.name: Dates.longDate(day.modelData) + (day.isToday ? ", today" : "")
                        Accessible.description: Calendar.events.length > 0 && Calendar.eventsOn(day.modelData).length > 0 ? Calendar.eventsOn(day.modelData).length + (Calendar.eventsOn(day.modelData).length === 1 ? " event" : " events") : ""
                        Accessible.selected: day.isSel
                        Accessible.onPressAction: cal.select(day.modelData)
                    }
                }
            }

            Rectangle { width: cal.cell * 7; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

            Item {
                width: cal.cell * 7
                height: Theme.sp(22)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Dates.longDate(cal.selected)     // the header's shape
                    size: 14
                    weight: Theme.wMedium
                }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: (cal.sameDay(cal.selected, cal.today) ? "Today · " : "") + "Week " + cal.week(cal.selected)
                    size: 12
                    color: Theme.textTertiary
                }
            }

            // ── That day's events (services/Calendar) ────────────────────────
            Column {
                width: cal.cell * 7
                spacing: 8
                readonly property var dayEvents: Calendar.eventsOn(cal.selected)
                Label {
                    visible: !Calendar.configured || parent.dayEvents.length === 0
                    width: parent.width
                    wrapMode: Text.Wrap
                    // Not set up: one click opens the list to paste a link into,
                    // instead of a path to go and find.
                    text: Calendar.configured ? "No events" : "No calendars yet. Add one: paste an iCal link or the path of an .ics file, one per line."
                    size: 12
                    color: !Calendar.configured && addCal.containsMouse ? Theme.textSecondary : Theme.textTertiary
                    Accessible.role: Calendar.configured ? Accessible.StaticText : Accessible.Button
                    Accessible.name: text
                    Accessible.onPressAction: if (!Calendar.configured) { Apps.run(["sh", "-c", 'mkdir -p "$(dirname "$1")" && touch "$1" && xdg-open "$1"', "sh", Calendar.listPath]); Island.close(); }
                    MouseArea {
                        id: addCal
                        anchors.fill: parent
                        enabled: !Calendar.configured
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: { Apps.run(["sh", "-c", 'mkdir -p "$(dirname "$1")" && touch "$1" && xdg-open "$1"', "sh", Calendar.listPath]); Island.close(); }
                    }
                }
                // As many as the island has room for: five, fewer as the text grows;
                // the rest as "+N more".
                readonly property int fits: Theme.textScale >= 1.5 ? 1 : Theme.textScale > 1 ? 3 : 5
                Repeater {
                    model: parent.dayEvents.slice(0, parent.fits)
                    Row {
                        id: evRow
                        required property var modelData
                        // The panel's clock (it was the real one: a day you were looking
                        // at ahead read as past). Past: quieter in colour, not faded (a
                        // faded time line fell under 3:1).
                        readonly property bool past: modelData.end < cal.now.getTime()
                        readonly property bool onNow: modelData.start <= cal.now.getTime() && !past
                        spacing: 10
                        Rectangle { width: 3; height: evCol.implicitHeight; radius: 1.5; color: evRow.onNow ? Theme.green : evRow.past ? Theme.textTertiary : Theme.textSecondary }
                        Column {
                            id: evCol
                            width: cal.cell * 7 - 13
                            spacing: 1
                            Label {
                                width: parent.width; elide: Text.ElideRight
                                wrapMode: Text.Wrap; maximumLineCount: 2
                                text: evRow.modelData.title; size: 13; weight: Theme.wMedium
                                color: evRow.past ? Theme.textTertiary : Theme.textPrimary
                            }
                            Label {
                                width: parent.width; elide: Text.ElideRight
                                text: Calendar.timeOf(evRow.modelData) + (evRow.modelData.location ? " · " + evRow.modelData.location : "")
                                size: 11; color: Theme.textTertiary
                            }
                        }
                    }
                }
                Label {
                    visible: parent.dayEvents.length > parent.fits
                    text: "+" + (parent.dayEvents.length - parent.fits) + " more"
                    size: 11; color: Theme.textTertiary
                }
            }
        }
    }
}
