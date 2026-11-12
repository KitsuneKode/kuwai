// The calendar, grown out of the island's clock: a month at a time, today as
// a white disc (Apple's), the selected day ringed. Keys: ←→ day, ↑↓ week,
// PgUp/PgDn (or [ ]) month, T today, Esc closes.
//
//   October 2026                          ‹  ›
//   Mon Tue Wed Thu Fri Sat Sun
//    28  29  30   1   2   3   4
//   …
//   Thursday, 29 October · week 44
import QtQuick
import qs.config
import qs.components
import qs.services

FocusScope {
    id: cal
    focus: true

    property date today: new Date()
    // The island's clock lands here (IslandBar's flyer); IslandBar keeps it ticking.
    property date now: new Date()
    readonly property Item clockItem: calClock
    property bool clockHidden: false
    property date selected: today
    // The month shown: its first day.
    property date month: new Date(today.getFullYear(), today.getMonth(), 1)

    readonly property int cell: 40
    implicitWidth: cell * 7 + 44
    implicitHeight: col.implicitHeight + 40

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
    // The 42 days on the grid: Monday first.
    readonly property var days: {
        const lead = (month.getDay() + 6) % 7;
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

    Column {
        id: col
        x: 22; y: 20
        spacing: 10

        Row {
            spacing: 10
            IslandClock {
                id: calClock
                visible: !cal.clockHidden
                now: cal.now; size: Theme.tClock
                rounded: false; weight: Theme.wMedium
                color: Qt.rgba(1, 0.98, 0.95, 0.95)
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(cal.now, "dddd, MMMM d")
                size: Theme.tHeadline; weight: Theme.wMedium
                color: Theme.textTertiary
            }
        }

        Item {
            width: cal.cell * 7
            height: 30
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7
                Label { text: Qt.formatDate(cal.month, "MMMM"); size: 20; weight: Theme.wSemibold }
                Label { anchors.baseline: parent.children[0].baseline; text: Qt.formatDate(cal.month, "yyyy"); size: 20; color: Theme.textTertiary }
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
                        Text { anchors.centerIn: parent; text: nav.modelData.g; font.family: Theme.fontGlyph; font.pixelSize: 16; color: Theme.textSecondary }
                        MouseArea { id: navArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cal.shiftMonth(nav.modelData.d) }
                    }
                }
            }
        }

        Row {
            Repeater {
                model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                Label {
                    required property string modelData
                    required property int index
                    width: cal.cell
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    size: 11
                    weight: Theme.wMedium
                    color: index >= 5 ? Theme.textTertiary : Theme.textSecondary
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
                        width: 32; height: 32; radius: 16
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
                        color: day.isToday ? "#111114" : !day.inMonth ? Qt.rgba(1, 1, 1, 0.25) : Theme.textPrimary
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
                }
            }
        }

        Rectangle { width: cal.cell * 7; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

        Item {
            width: cal.cell * 7
            height: 22
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(cal.selected, "dddd, d MMMM")
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
                text: Calendar.configured ? "No events" : "Add your calendars (iCal links or .ics files) to ~/.config/rice/calendars.txt"
                size: 12
                color: Theme.textTertiary
            }
            Repeater {
                model: parent.dayEvents.slice(0, 5)
                Row {
                    id: evRow
                    required property var modelData
                    readonly property bool past: modelData.end < Date.now()
                    spacing: 10
                    opacity: past ? 0.45 : 1
                    Rectangle { width: 3; height: 30; radius: 1.5; color: evRow.modelData.start <= Date.now() && !evRow.past ? Theme.green : Theme.textSecondary }
                    Column {
                        width: cal.cell * 7 - 13
                        spacing: 1
                        Label { width: parent.width; elide: Text.ElideRight; text: evRow.modelData.title; size: 13; weight: Theme.wMedium }
                        Label {
                            width: parent.width; elide: Text.ElideRight
                            text: Calendar.timeOf(evRow.modelData) + (evRow.modelData.location ? " · " + evRow.modelData.location : "")
                            size: 11; color: Theme.textTertiary
                        }
                    }
                }
            }
            Label {
                visible: parent.dayEvents.length > 5
                text: "+" + (parent.dayEvents.length - 5) + " more"
                size: 11; color: Theme.textTertiary
            }
        }
    }
}
