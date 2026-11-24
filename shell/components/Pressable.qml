import QtQuick
import qs.config

FocusScope {
    id: btn
    property bool disabled: false
    property real radius: Theme.r2
    property string accessibleName: ""
    property int accessibleRole: Accessible.Button
    property bool hoverWash: true
    property real pressScale: 0.98
    readonly property bool hovered: hover.hovered && !disabled
    readonly property bool pressed: area.pressed && !disabled

    signal clicked()
    signal rightClicked(real mx, real my)

    Accessible.role: accessibleRole
    Accessible.name: accessibleName
    Accessible.ignored: accessibleName === ""
    Accessible.onPressAction: if (!disabled) clicked()

    activeFocusOnTab: !disabled
    opacity: disabled ? 0.45 : 1.0
    scale: (!Theme.reduceMotion && pressed) ? pressScale : 1.0
    Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.pressMs; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: btn.radius
        color: btn.pressed ? Theme.wash(2) : (btn.hoverWash && btn.hovered) ? Theme.wash(1) : "transparent"
        Behavior on color { enabled: !Theme.reduceMotion; ColorAnimation { duration: Theme.hoverMs } }
    }

    FocusRing {
        cornerRadius: btn.radius
    }

    HoverHandler {
        id: hover
        enabled: !btn.disabled
        cursorShape: btn.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: !btn.disabled
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) btn.rightClicked(mouse.x, mouse.y);
            else btn.clicked();
        }
    }

    Keys.onPressed: e => {
        if (btn.disabled) return;
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
            e.accepted = true;
            btn.clicked();
        }
    }
}
