// Island bell: glyph + capped badge (9+). Click → center; right-click / hold → quick list (QuickIcon rules).
import QtQuick
import qs.config

Item {
    id: bell
    property int count: 0
    property bool muted: false
    property bool dnd: false
    property bool missed: false
    property bool urgent: false
    property string tip: ""
    property bool suppressTip: false
    property color badgeTone: Theme.accent
    signal tapped()
    signal quickPressed()

    implicitWidth: 34
    implicitHeight: 26

    Icon {
        id: glyph
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: count > 0 && !muted ? -2 : 0
        name: muted ? "bell-slash" : "bell"
        size: 18
        active: count > 0 || missed
        color: dnd ? Theme.focus : muted ? Theme.textTertiary : (count > 0 ? Theme.accent : Theme.textSecondary)
    }

    Rectangle {
        visible: count > 0 && !muted
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: -1
        height: 16
        radius: 8
        width: Math.max(16, badgeLbl.implicitWidth + 8)
        color: badgeTone
        border.width: 1.5
        border.color: Qt.rgba(0, 0, 0, 0.85)
        Label {
            id: badgeLbl
            anchors.centerIn: parent
            text: count > 9 ? "9+" : String(count)
            size: 10
            weight: Theme.wSemibold
            rounded: true
            color: "#111111"
            font.features: ({ "tnum": 1 })
        }
    }

    Rectangle {
        visible: count === 0 && missed && !muted
        anchors.right: glyph.right
        anchors.top: glyph.top
        anchors.rightMargin: -2
        anchors.topMargin: -1
        width: 8
        height: 8
        radius: 4
        color: urgent ? Theme.critical : Theme.orange
        border.width: 1.5
        border.color: Qt.rgba(0, 0, 0, 0.85)
    }

    property bool holdDone: false

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        pressAndHoldInterval: 350
        onPressed: m => { if (m.button === Qt.LeftButton) bell.holdDone = false; }
        onPressAndHold: { bell.holdDone = true; bell.quickPressed(); }
        onClicked: m => {
            if (bell.holdDone) { bell.holdDone = false; return; }
            if (m.button === Qt.RightButton || (m.modifiers & Qt.ControlModifier))
                bell.quickPressed();
            else
                bell.tapped();
        }
    }

    Tip {
        text: bell.tip + "\nClick: center · Right-click, hold or Ctrl+click: quick list"
        shown: area.containsMouse && !bell.suppressTip
        below: true
    }
    FocusRing { cornerRadius: 13; gap: 2 }
}
