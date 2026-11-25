import QtQuick
import qs.config
import qs.components
import qs.services

Rectangle {
    id: today
    property real now: Date.now()
    Timer { interval: 60000; running: today.visible; repeat: true; triggeredOnStart: true; onTriggered: today.now = Date.now() }
    readonly property var next: {
        const end = new Date(now); end.setHours(23, 59, 59, 999);
        const later = end.getTime() + 86400000;
        return (Calendar.events || []).find(e => !e.allDay && e.end > now && e.start < later) || null;
    }
    function open() { Notifs.setCenter(false, "key"); Island.open("calendar", Notifs.centerScreen, "key"); }
    activeFocusOnTab: true
    Keys.onReturnPressed: open()
    Keys.onEnterPressed: open()
    Keys.onSpacePressed: open()
    FocusRing { cornerRadius: Theme.r3 }
    height: Math.max(Theme.sp(64), textCol.implicitHeight + Theme.s4)
    radius: Theme.r3
    color: Theme.card
    border.width: 1
    border.color: Theme.cardEdge

    Row {
        anchors { fill: parent; leftMargin: Theme.s3; rightMargin: Theme.s3 }
        spacing: Theme.s3
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.sp(52)
            Label { text: Dates.shortDate(today.now).split(/[, ]+/)[0]; size: Theme.tFootnote; weight: Theme.wSemibold; color: Theme.red }
            Label { text: String(new Date(today.now).getDate()); size: Theme.tTitle2; weight: Theme.wSemibold; color: Theme.textPrimary; tabular: true }
        }
        Rectangle { width: 1; height: parent.height - Theme.s4; anchors.verticalCenter: parent.verticalCenter; color: Theme.wash(1) }
        Column {
            id: textCol
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.sp(52) - weather.width - 1 - Theme.s3 * 3
            spacing: 2
            Label {
                width: parent.width
                text: today.next ? today.next.title : "Nothing else today"
                size: Theme.tBody; weight: Theme.wMedium
                color: today.next ? Theme.textPrimary : Theme.textSecondary
                wrapMode: Text.Wrap; maximumLineCount: 2
                elide: Text.ElideRight
            }
            Label {
                width: parent.width
                text: today.next ? (today.next.start <= today.now ? "Now · until " + Dates.time(today.next.end)
                                    : Dates.day(today.next.start, today.now) + " · " + Dates.time(today.next.start))
                               : Dates.longDate(today.now)
                size: Theme.tFootnote; color: Theme.textTertiary
                wrapMode: Text.Wrap; maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
        Row {
            id: weather
            visible: Weather.ok
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s1
            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Weather.glyph
                font.family: Theme.fontGlyph; font.pixelSize: Theme.tTitle3
                color: Theme.textSecondary
            }
            Label { anchors.verticalCenter: parent.verticalCenter; text: Weather.temp + "°"; size: Theme.tHeadline; weight: Theme.wSemibold; tabular: true }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        Accessible.ignored: true
        onClicked: { Notifs.setCenter(false, "pointer"); Island.open("calendar", Notifs.centerScreen, "pointer"); }
    }
    Accessible.role: Accessible.Button
    Accessible.name: "Today, " + Dates.longDate(today.now) + (today.next ? ". Next: " + today.next.title : "") + (Weather.ok ? ". " + Weather.temp + " degrees" : "") + ". Open the calendar"
}
