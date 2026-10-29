// When was it copied? A calendar that grows out of its button (the same
// morph as the action menu): quick ranges on the left (Today, Yesterday,
// Last 7 days, This month, Any time), a month on the right whose days carry
// a dot sized by how much was copied that day. Click a day for that day;
// ⇧-click another for the range between. ←→ change month, Esc closes.
//
// Days come from copy times the rice recorded (and when pins were made):
// cliphist doesn't keep times, so history from before then has no day.
import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: dp

    property Item anchorItem
    property bool open: false
    property var counts: ({})                 // "YYYY-MM-DD" → entries copied that day
    property real from: 0                     // ms, inclusive; 0 = no lower bound
    property real to: 0                       // ms, exclusive; 0 = no upper bound
    signal picked(real from, real to, string label)

    anchors.fill: parent
    visible: t.value > 0.002 || open
    z: 30

    function toggle() { open = !open; }
    onOpenChanged: {
        if (open) {
            src = anchorItem ? anchorItem.mapToItem(dp, 0, 0, anchorItem.width, anchorItem.height) : Qt.rect(width - 40, 20, 40, 30);
            const base = from ? new Date(from) : new Date();
            month = new Date(base.getFullYear(), base.getMonth(), 1);
        }
        t.target = open ? 1 : 0;
        if (Theme.reduceMotion) t.settle();
    }
    function key(event) {
        if (!open) return false;
        if (event.key === Qt.Key_Escape) open = false;
        else if (event.key === Qt.Key_Left) shift(-1);
        else if (event.key === Qt.Key_Right) shift(1);
        return true;
    }

    // ── Dates ────────────────────────────────────────────────────────────
    function dayKey(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
    function startOf(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); }
    readonly property real day: 86400000
    property date month: new Date()
    function shift(n) { month = new Date(month.getFullYear(), month.getMonth() + n, 1); }
    readonly property var cells: {
        const first = new Date(month.getFullYear(), month.getMonth(), 1);
        const lead = (first.getDay() + 6) % 7;                  // weeks start on Monday
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(first.getFullYear(), first.getMonth(), 1 - lead + i);
            out.push({ d: d, key: dayKey(d), inMonth: d.getMonth() === first.getMonth() });
        }
        return out;
    }
    readonly property int maxCount: Math.max(1, ...Object.values(counts))
    property real anchorDay: 0
    function pickDay(d, extend) {
        const s = startOf(d);
        if (extend && anchorDay) {
            const a = Math.min(anchorDay, s), b = Math.max(anchorDay, s) + day;
            picked(a, b, fmt(a) + " – " + fmt(b - day));
        } else {
            anchorDay = s;
            picked(s, s + day, fmt(s));
        }
    }
    function fmt(ms) { return new Date(ms).toLocaleDateString(Qt.locale(), "d MMM"); }
    function quick(id) {
        const now = new Date(), today = startOf(now);
        if (id === "today") picked(today, today + day, "Today");
        else if (id === "yesterday") picked(today - day, today, "Yesterday");
        else if (id.startsWith("ago:")) {
            const n = Number(id.slice(4)), s = today - n * day;
            picked(s, s + day, new Date(s).toLocaleDateString(Qt.locale(), "ddd d MMM"));
        }
        else if (id === "week") picked(today - 6 * day, today + day, "Last 7 days");
        else if (id === "month") picked(new Date(now.getFullYear(), now.getMonth(), 1).getTime(), today + day, "This month");
        else picked(0, 0, "");
        open = false;
    }

    // ── Geometry: grows out of its button, downward ──────────────────────
    property rect src: Qt.rect(0, 0, 40, 30)
    readonly property real toW: 420
    readonly property real toH: 316
    readonly property real toX: Math.max(8, Math.min(width - toW - 8, src.x + src.width - toW))
    readonly property real toY: Math.min(height - toH - 8, src.y + src.height + 6)
    Spring { id: t; tier: Theme.springModerate; epsilon: 0.001 }
    function lerp(a, b, k) { return a + (b - a) * k; }

    MouseArea { anchors.fill: parent; enabled: dp.open; onClicked: dp.open = false }

    Rectangle {
        id: frame
        x: dp.lerp(dp.src.x, dp.toX, t.value)
        y: dp.lerp(dp.src.y, dp.toY, t.value)
        width: Math.max(1, dp.lerp(dp.src.width, dp.toW, t.value))
        height: Math.max(1, dp.lerp(dp.src.height, dp.toH, t.value))
        radius: dp.lerp(dp.src.height / 2, 16, Math.min(1, t.value))
        color: Qt.rgba(0.09, 0.09, 0.105, 0.98)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
        opacity: Math.min(1, t.value * 4)
        clip: true
        MouseArea { anchors.fill: parent }

        Item {
            width: dp.toW
            height: dp.toH
            x: (frame.width - width) * (1 - Math.min(1, t.value))
            opacity: Math.max(0, Math.min(1, (t.value - 0.45) / 0.4))

            // Quick ranges
            Column {
                id: quickCol
                x: 10; y: 12
                width: 118
                spacing: 2
                Repeater {
                    // Today, Yesterday, then the days before by name (Mon 27…),
                    // each with how much was copied that day.
                    model: {
                        const day = 86400000, now = new Date(), today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
                        const out = [{ id: "today", t: "Today", ms: today }, { id: "yesterday", t: "Yesterday", ms: today - day }];
                        for (let n = 2; n <= 5; n++) out.push({ id: "ago:" + n, t: new Date(today - n * day).toLocaleDateString(Qt.locale(), "ddd d"), ms: today - n * day });
                        out.push({ id: "week", t: "Last 7 days" }, { id: "month", t: "This month" }, { id: "any", t: "Any time" });
                        return out;
                    }
                    Rectangle {
                        id: q
                        required property var modelData
                        width: quickCol.width
                        height: 28
                        radius: 8
                        color: qa.containsMouse ? Qt.alpha(Theme.blue, 0.85) : "transparent"
                        Label { x: 10; anchors.verticalCenter: parent.verticalCenter; text: q.modelData.t; size: 13; color: qa.containsMouse ? "white" : Theme.textPrimary }
                        Label {
                            readonly property int n: q.modelData.ms ? (dp.counts[dp.dayKey(new Date(q.modelData.ms))] || 0) : 0
                            visible: n > 0
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: n
                            size: 11
                            rounded: true
                            color: qa.containsMouse ? "white" : Theme.textTertiary
                        }
                        MouseArea { id: qa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dp.quick(q.modelData.id) }
                    }
                }
            }
            Rectangle { x: quickCol.x + quickCol.width + 8; y: 12; width: 1; height: dp.toH - 24; color: Qt.rgba(1, 1, 1, 0.08) }

            // Month
            Item {
                id: cal
                x: quickCol.x + quickCol.width + 18
                y: 10
                width: dp.toW - x - 12
                height: dp.toH - 20
                readonly property real cellW: width / 7

                Label {
                    id: monthLabel
                    x: 4
                    height: 28
                    verticalAlignment: Text.AlignVCenter
                    text: dp.month.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                    size: 14
                    weight: Theme.wSemibold
                }
                Row {
                    anchors { right: parent.right; verticalCenter: monthLabel.verticalCenter }
                    spacing: 2
                    Repeater {
                        model: [{ g: "\u{f0141}", n: -1 }, { g: "\u{f0142}", n: 1 }]
                        Rectangle {
                            id: nav
                            required property var modelData
                            width: 26; height: 26; radius: 8
                            color: na.containsMouse ? Theme.pillHover : "transparent"
                            Text { anchors.centerIn: parent; text: nav.modelData.g; font.family: Theme.fontGlyph; font.pixelSize: 15; color: Theme.textSecondary }
                            MouseArea { id: na; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dp.shift(nav.modelData.n) }
                        }
                    }
                }
                Row {
                    id: weekdays
                    y: 32
                    Repeater {
                        model: ["M", "T", "W", "T", "F", "S", "S"]
                        Label { required property string modelData; width: cal.cellW; horizontalAlignment: Text.AlignHCenter; text: modelData; size: 11; color: Theme.textTertiary }
                    }
                }
                Grid {
                    y: 52
                    columns: 7
                    Repeater {
                        model: dp.cells
                        Item {
                            id: cell
                            required property var modelData
                            readonly property real ms: dp.startOf(modelData.d)
                            readonly property int n: dp.counts[modelData.key] || 0
                            readonly property bool inRange: dp.from > 0 && ms >= dp.from && ms < (dp.to || Infinity)
                            readonly property bool today: modelData.key === dp.dayKey(new Date())
                            width: cal.cellW
                            height: 34
                            Rectangle {
                                anchors.centerIn: parent
                                width: 30; height: 30; radius: 15
                                color: cell.inRange ? Theme.blue : ca.containsMouse ? Theme.pillHover : "transparent"
                                border.width: cell.today && !cell.inRange ? 1 : 0
                                border.color: Theme.blue
                            }
                            Label {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -2
                                text: cell.modelData.d.getDate()
                                size: 12
                                rounded: true
                                weight: cell.n > 0 ? Theme.wSemibold : Theme.wRegular
                                color: cell.inRange ? "white" : !cell.modelData.inMonth ? Theme.textTertiary : cell.n > 0 ? Theme.textPrimary : Theme.textSecondary
                                opacity: cell.modelData.inMonth ? 1 : 0.5
                            }
                            // How much was copied that day.
                            Rectangle {
                                visible: cell.n > 0
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 5 }
                                width: 3 + Math.round(5 * cell.n / dp.maxCount); height: 3; radius: 1.5
                                color: cell.inRange ? "white" : Theme.blue
                            }
                            MouseArea {
                                id: ca
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => dp.pickDay(cell.modelData.d, mouse.modifiers & Qt.ShiftModifier)
                            }
                        }
                    }
                }
            }
        }
    }
}
