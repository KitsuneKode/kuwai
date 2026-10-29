// One notification inside the center: a lighter plate on the panel's glass.
// Click opens it (the app's default action if the notification is still
// live, then its window); the hover close button removes it, collapsing the
// space it took so the rows below glide up.
import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: row

    required property var item
    property var center                         // the NotificationsView
    property bool showTime: true
    readonly property bool selected: center && center.selected === item
    onSelectedChanged: if (selected && center) center.selectedRow = row
    Component.onDestruction: if (center && center.hoverRow === row) center.hoverRow = null

    readonly property bool critical: item.severity === "critical"
    readonly property bool warning: item.severity === "warning"
    readonly property color accent: critical ? Theme.red : warning ? Theme.orange : "transparent"
    readonly property bool unread: item.time > Notifs.lastSeen

    property real reveal: 0
    property bool removing: false

    width: parent ? parent.width : 0
    height: (body.implicitHeight + 24) * reveal
    opacity: reveal
    clip: reveal < 1

    Component.onCompleted: {
        if (center && center.instant) reveal = 1;
        else grow.start();
    }
    // Reused for another notification (the top of a folded stack after its
    // first one was removed): show the new one whole.
    onItemChanged: if (removing) { shrink.stop(); removing = false; grow.start(); }
    NumberAnimation { id: grow; target: row; property: "reveal"; to: 1; duration: Theme.reduceMotion ? 0 : Theme.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    NumberAnimation {
        id: shrink; target: row; property: "reveal"; to: 0; duration: Theme.exitMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut
        onFinished: row.item.popup ? Notifs.dismiss(row.item) : Notifs.remove(row.item)
    }
    function remove() {
        if (removing) return;
        removing = true;
        grow.stop();
        shrink.start();
    }

    HoverHandler {
        id: hover
        onHoveredChanged: if (row.center) row.center.setHover(row, hovered)
        cursorShape: row.item.notification || row.item.focusClass ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    // Press feedback, kept tiny: rows are hit often.
    scale: tapH.pressed ? 0.985 : 1
    Behavior on scale { NumberAnimation { duration: Theme.pressMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    TapHandler {
        id: tapH
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (point, button) => {
            if (button === Qt.RightButton) row.remove();
            else Notifs.openItem(row.item);
        }
    }

    Rectangle {
        id: plate
        anchors.fill: parent
        radius: 18
        // Hover and the keyboard ring are the view's one gliding highlight.
        color: Qt.rgba(1, 1, 1, 0.065)
        border.width: 1
        border.color: row.critical || row.warning ? Qt.alpha(row.accent, 0.35) : Qt.rgba(1, 1, 1, 0.06)

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: row.critical || row.warning
            color: Qt.alpha(row.accent, row.critical ? 0.12 : 0.07)
        }
    }

    Column {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 14; rightMargin: 14 }
        spacing: 3

        Item {
            width: parent.width
            height: Math.max(titleText.implicitHeight, 18)

            Row {
                id: titleRow
                anchors.left: parent.left
                anchors.right: meta.left
                anchors.rightMargin: 8
                spacing: 6

                Rectangle {
                    visible: row.critical || row.warning
                    anchors.verticalCenter: titleText.verticalCenter
                    height: 16; radius: 8
                    width: chip.implicitWidth + 12
                    color: Qt.alpha(row.accent, 0.24)
                    Label {
                        id: chip
                        anchors.centerIn: parent
                        text: row.critical ? "Critical" : "Warning"
                        size: 11
                        weight: Theme.wSemibold
                        color: row.critical ? "#ff6961" : Theme.orange
                    }
                }
                Label {
                    id: titleText
                    width: titleRow.width - (row.critical || row.warning ? chip.implicitWidth + 18 : 0)
                    text: row.center ? row.center.highlight(row.item.title) : row.item.title
                    textFormat: Text.StyledText
                    elide: Text.ElideRight
                    size: 14
                    weight: Theme.wSemibold
                }
            }
            Row {
                id: meta
                anchors.right: parent.right
                anchors.verticalCenter: titleRow.verticalCenter
                spacing: 6
                // Unread dot: Apple's blue, gone once the center has been seen.
                Rectangle {
                    visible: row.unread
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7; height: 7; radius: 3.5
                    color: Theme.blue
                }
                Label {
                    visible: row.showTime && !hover.hovered
                    text: row.ageText
                    size: 12
                    font.features: ({ "tnum": 1 })
                    color: Theme.textTertiary
                }
                // Close, in place of the time while hovered
                Rectangle {
                    visible: hover.hovered
                    width: 20; height: 20; radius: 10
                    color: closeArea.containsMouse ? Theme.pillHover : Theme.pill
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0156}"
                        font.family: Theme.fontGlyph
                        font.pixelSize: 11
                        color: Theme.textPrimary
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.remove()
                    }
                }
            }
        }

        Label {
            width: parent.width
            // Bodies may carry markup; matches highlight on the plain text.
            text: row.center && row.center.terms.length ? row.center.highlight(row.item.body.replace(/<[^>]*>/g, "")) : row.item.body
            visible: row.item.body !== ""
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            size: 13
            lineHeight: 1.18
            color: Theme.textSecondary
        }

        Row {
            visible: row.item.status !== ""
            spacing: 6
            topPadding: 2
            Text {
                visible: row.item.statusGlyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: row.item.statusGlyph
                font.family: Theme.fontGlyph
                font.pixelSize: 13
                color: row.item.statusTone === "positive" ? Theme.positive
                     : row.item.statusTone === "caution" ? Theme.caution
                     : row.item.statusTone === "critical" ? Theme.critical
                     : Theme.textSecondary
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: row.item.status
                size: 12
                weight: Theme.wMedium
                color: Theme.textSecondary
            }
        }
    }

    property string ageText: ""
    Timer {
        running: row.visible
        repeat: true
        triggeredOnStart: true
        interval: 30000
        onTriggered: {
            const m = Math.floor((Date.now() - row.item.time) / 60000);
            const d = Math.floor(m / 1440);
            row.ageText = m < 1 ? "now" : m < 60 ? m + "m" : m < 1440 ? Math.floor(m / 60) + "h" : d + "d";
        }
    }
}
